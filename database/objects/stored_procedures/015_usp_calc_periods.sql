
/****** Object:  StoredProcedure [dbo].[usp_calc_periods]    Script Date: 22/12/2025 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_calc_periods]
  @client_id NVARCHAR(50)
AS
BEGIN
  /*
  ================================================================================
  Procedure: usp_calc_periods
  Purpose:   Calculate period-based metrics for employees comparing baseline 
             vs recent periods. Uses emp_work_calendar for presence calculations
             and per-employee workday calculations based on their individual
             period boundaries.
  
  Parameters:
    @client_id - Client identifier (required)
  
  Returns:   None (inserts into calc_period_metrics and calculated_data tables)
  
  Multi-tenant: Yes - all operations filtered by @client_id
  Transaction:  Yes - wrapped in explicit transaction with error handling
  ================================================================================
  */
  
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  
  DECLARE @ErrorMessage NVARCHAR(4000);
  DECLARE @ErrorSeverity INT;
  DECLARE @ErrorState INT;
  DECLARE @TransactionCount INT = @@TRANCOUNT;
  
  BEGIN TRY
    -- ========================================================================
    -- STEP 1: VALIDATION & GUARD CLAUSES
    -- ========================================================================
    
    IF @client_id IS NULL OR LTRIM(RTRIM(@client_id)) = N''
    BEGIN
      RAISERROR('usp_calc_periods: @client_id is required and cannot be empty.', 16, 1);
      RETURN;
    END
    
    IF NOT EXISTS (SELECT 1 FROM dbo.work_calendar WHERE client_id = @client_id)
    BEGIN
      RAISERROR('usp_calc_periods: No work_calendar data found for client_id=%s.', 16, 1, @client_id);
      RETURN;
    END
    
    -- ========================================================================
    -- STEP 2: BEGIN TRANSACTION
    -- ========================================================================
    
    IF @TransactionCount = 0
      BEGIN TRANSACTION;
    
    -- ========================================================================
    -- STEP 3: LOAD CONFIGURATION PARAMETERS (from risk_config)
    -- ========================================================================
    
    DECLARE 
      @baseline_months INT,
      @recent_months INT,
      @last_company_workday DATE;
    
    -- Get baseline_months (client-specific -> global -> default 9)
    SELECT TOP(1) @baseline_months = TRY_CAST(config_value AS INT)
    FROM dbo.risk_config
    WHERE (client_id = @client_id OR client_id IS NULL) 
      AND config_key = N'baseline_months'
    ORDER BY CASE WHEN client_id = @client_id THEN 0 ELSE 1 END;
    
    IF @baseline_months IS NULL SET @baseline_months = 9;
    
    -- Get recent_months (client-specific -> global -> default 3)
    SELECT TOP(1) @recent_months = TRY_CAST(config_value AS INT)
    FROM dbo.risk_config
    WHERE (client_id = @client_id OR client_id IS NULL) 
      AND config_key = N'recent_months'
    ORDER BY CASE WHEN client_id = @client_id THEN 0 ELSE 1 END;
    
    IF @recent_months IS NULL SET @recent_months = 3;
    
    -- ========================================================================
    -- STEP 4: BUILD BASE EMPLOYEE UNIVERSE (calc_periods_emp)
    -- ========================================================================
    -- Filter: Only employees who have worked at least 6 months AND worked in past 2 months
    -- This is the foundation table that all other calculations will join to
    
    IF OBJECT_ID('tempdb..#calc_periods_emp') IS NOT NULL DROP TABLE #calc_periods_emp;
    
    SELECT 
      ewc.client_id,
      ewc.emp_id,
      COALESCE(emp.work_start, ewc.first_session_date) AS emp_work_start,
      ewc.last_session_date AS last_emp_workday,
      wc.last_company_workday
    INTO #calc_periods_emp
    FROM 
    (
      -- Get employee work date ranges from emp_work_calendar
      SELECT 
        client_id,
        emp_id,
        MIN(CAST(calendar_date AS DATE)) AS first_session_date,
        MAX(CAST(calendar_date AS DATE)) AS last_session_date
      FROM dbo.emp_work_calendar
      WHERE client_id = @client_id
        AND is_working = 1
      GROUP BY client_id, emp_id
    ) AS ewc
    LEFT JOIN 
    (
      -- Get employee work_start from employees table if available
      SELECT client_id, emp_id, work_start
      FROM dbo.employees
      WHERE client_id = @client_id
    ) AS emp
      ON ewc.client_id = emp.client_id
      AND ewc.emp_id = emp.emp_id
    LEFT JOIN 
    (
      -- Get last company workday
      SELECT 
        client_id, 
        MAX(calendar_date) AS last_company_workday
      FROM dbo.work_calendar
      WHERE client_id = @client_id
        AND is_workday = 1
      GROUP BY client_id
    ) AS wc
      ON ewc.client_id = wc.client_id
    WHERE 
      -- Filter 1: Employee must have worked for at least 6 months
      COALESCE(emp.work_start, ewc.first_session_date) <= DATEADD(MONTH, -4, wc.last_company_workday)
      -- Filter 2: Employee must have worked in the past 2 months
      AND ewc.last_session_date >= DATEADD(MONTH, -2, wc.last_company_workday);
    
    -- Check if we have any eligible employees
    IF NOT EXISTS (SELECT 1 FROM #calc_periods_emp)
    BEGIN
      -- No eligible employees - this is acceptable, just exit gracefully
      IF @TransactionCount = 0 COMMIT TRANSACTION;
      RETURN;
    END
    
    -- ========================================================================
    -- STEP 5: CALCULATE PERIOD BOUNDARIES (recent_start, recent_end, baseline_start, baseline_end)
    -- ========================================================================
    -- Each employee gets their own periods based on their work_start date
    
    IF OBJECT_ID('tempdb..#emp_periods') IS NOT NULL DROP TABLE #emp_periods;
    
    SELECT 
      client_id,
      emp_id,
      emp_work_start,
      last_emp_workday,
      last_company_workday,
      
      -- Calculate recent_start
      CASE 
        WHEN DATEDIFF(MONTH, emp_work_start, last_company_workday) >= (@baseline_months + @recent_months)
        THEN DATEADD(MONTH, -@recent_months, last_company_workday)
        ELSE DATEADD(MONTH, -2, last_company_workday)
      END AS recent_start,
      
      -- recent_end is always last_company_workday
      last_company_workday AS recent_end,
      
      -- Calculate baseline_start
      CASE 
        WHEN DATEDIFF(MONTH, emp_work_start, last_company_workday) >= (@baseline_months + @recent_months)
        THEN DATEADD(MONTH, -(@baseline_months + @recent_months), last_company_workday)
        ELSE emp_work_start
      END AS baseline_start,
      
      -- baseline_end is always one day before recent_start
      CASE 
        WHEN DATEDIFF(MONTH, emp_work_start, last_company_workday) >= (@baseline_months + @recent_months)
        THEN DATEADD(DAY, -1, DATEADD(MONTH, -@recent_months, last_company_workday))
        ELSE DATEADD(DAY, -1, DATEADD(MONTH, -2, last_company_workday))
      END AS baseline_end
      
    INTO #emp_periods
    FROM #calc_periods_emp;
    
    -- ========================================================================
    -- STEP 6: DELETE EXISTING DATA FOR THIS CLIENT
    -- ========================================================================
    
    DELETE FROM dbo.calc_period_metrics
    WHERE client_id = @client_id;
    
    -- ========================================================================
    -- STEP 7: CALCULATE WORKDAYS (PER EMPLOYEE based on their period boundaries)
    -- ========================================================================
    -- Each employee gets workdays calculated for THEIR specific recent/baseline dates
    
    IF OBJECT_ID('tempdb..#workdays') IS NOT NULL DROP TABLE #workdays;
    
    SELECT 
      ep.client_id,
      ep.emp_id,
      -- Workdays in recent period (for this employee's specific dates)
      SUM(CASE 
        WHEN wc.calendar_date BETWEEN ep.recent_start AND ep.recent_end 
        THEN wc.is_workday 
        ELSE 0 
      END) AS workdays_r,
      -- Workdays in baseline period (for this employee's specific dates)
      SUM(CASE 
        WHEN wc.calendar_date BETWEEN ep.baseline_start AND ep.baseline_end 
        THEN wc.is_workday 
        ELSE 0 
      END) AS workdays_b
    INTO #workdays
    FROM #emp_periods ep
    CROSS JOIN dbo.work_calendar wc
    WHERE wc.client_id = @client_id
      AND wc.calendar_date BETWEEN ep.baseline_start AND ep.recent_end
    GROUP BY ep.client_id, ep.emp_id;
    
    -- ========================================================================
    -- STEP 8: CALCULATE PRESENCE (using emp_work_calendar.is_working)
    -- ========================================================================
    -- Use emp_work_calendar.is_working (SUM) instead of counting distinct dates from emp_sessions
    
    IF OBJECT_ID('tempdb..#presence') IS NOT NULL DROP TABLE #presence;
    
    SELECT 
      ep.client_id,
      ep.emp_id,
      -- Presence in recent period (sum of is_working where is_workday = 1)
      SUM(CASE 
        WHEN ewc.calendar_date BETWEEN ep.recent_start AND ep.recent_end 
          AND wc.is_workday = 1 
        THEN COALESCE(ewc.is_working, 0) 
        ELSE 0 
      END) AS presence_r,
      -- Presence in baseline period
      SUM(CASE 
        WHEN ewc.calendar_date BETWEEN ep.baseline_start AND ep.baseline_end 
          AND wc.is_workday = 1 
        THEN COALESCE(ewc.is_working, 0) 
        ELSE 0 
      END) AS presence_b,
      -- Non-workday presence in recent period
      SUM(CASE 
        WHEN ewc.calendar_date BETWEEN ep.recent_start AND ep.recent_end 
          AND wc.is_workday = 0 
        THEN COALESCE(ewc.is_working, 0) 
        ELSE 0 
      END) AS non_workday_presence_r,
      -- Non-workday presence in baseline period
      SUM(CASE 
        WHEN ewc.calendar_date BETWEEN ep.baseline_start AND ep.baseline_end 
          AND wc.is_workday = 0 
        THEN COALESCE(ewc.is_working, 0) 
        ELSE 0 
      END) AS non_workday_presence_b
    INTO #presence
    FROM #emp_periods ep
    LEFT JOIN dbo.emp_work_calendar ewc
      ON ewc.client_id = ep.client_id
      AND ewc.emp_id = ep.emp_id
      AND ewc.calendar_date BETWEEN ep.baseline_start AND ep.recent_end
    LEFT JOIN dbo.work_calendar wc
      ON wc.client_id = ep.client_id
      AND wc.calendar_date = ewc.calendar_date
    GROUP BY ep.client_id, ep.emp_id;
    
    -- ========================================================================
    -- STEP 9: CALCULATE TIME METRICS (avg_minutes, avg_arrival, avg_departure)
    -- ========================================================================
    
    IF OBJECT_ID('tempdb..#time_metrics') IS NOT NULL DROP TABLE #time_metrics;
    
    SELECT 
      ep.client_id,
      ep.emp_id,
      -- Average minutes worked
      AVG(CASE 
        WHEN CAST(es.session_start AS DATE) BETWEEN ep.recent_start AND ep.recent_end 
        THEN CAST(es.minutes_worked AS FLOAT)
        ELSE NULL 
      END) AS avg_minutes_r,
      AVG(CASE 
        WHEN CAST(es.session_start AS DATE) BETWEEN ep.baseline_start AND ep.baseline_end 
        THEN CAST(es.minutes_worked AS FLOAT)
        ELSE NULL 
      END) AS avg_minutes_b,
      -- Average arrival time (session_start time)
      CAST(DATEADD(
        SECOND,
        AVG(CASE 
          WHEN CAST(es.session_start AS DATE) BETWEEN ep.recent_start AND ep.recent_end 
          THEN DATEDIFF(SECOND, '00:00:00', CAST(es.session_start AS TIME))
          ELSE NULL
        END),
        '00:00:00'
      ) AS TIME) AS avg_arrival_r,
      CAST(DATEADD(
        SECOND,
        AVG(CASE 
          WHEN CAST(es.session_start AS DATE) BETWEEN ep.baseline_start AND ep.baseline_end 
          THEN DATEDIFF(SECOND, '00:00:00', CAST(es.session_start AS TIME))
          ELSE NULL
        END),
        '00:00:00'
      ) AS TIME) AS avg_arrival_b,
      -- Average departure time (session_end time)
      CAST(DATEADD(
        SECOND,
        AVG(CASE 
          WHEN CAST(es.session_end AS DATE) BETWEEN ep.recent_start AND ep.recent_end 
          THEN DATEDIFF(SECOND, '00:00:00', CAST(es.session_end AS TIME))
          ELSE NULL
        END),
        '00:00:00'
      ) AS TIME) AS avg_departure_r,
      CAST(DATEADD(
        SECOND,
        AVG(CASE 
          WHEN CAST(es.session_end AS DATE) BETWEEN ep.baseline_start AND ep.baseline_end 
          THEN DATEDIFF(SECOND, '00:00:00', CAST(es.session_end AS TIME))
          ELSE NULL
        END),
        '00:00:00'
      ) AS TIME) AS avg_departure_b
    INTO #time_metrics
    FROM #emp_periods ep
    LEFT JOIN dbo.emp_sessions es
      ON es.client_id = ep.client_id
      AND es.emp_id = ep.emp_id
      AND CAST(es.session_start AS DATE) BETWEEN ep.baseline_start AND ep.recent_end
    GROUP BY ep.client_id, ep.emp_id;
    
    -- ========================================================================
    -- STEP 10: ASSEMBLE FINAL RESULTS WITH ALL CALCULATIONS
    -- ========================================================================
    
    IF OBJECT_ID('tempdb..#final_metrics') IS NOT NULL DROP TABLE #final_metrics;
    
    SELECT 
      ep.client_id,
      ep.emp_id,
      
      -- Period boundaries (as DATETIME for table compatibility)
      CAST(ep.recent_start AS DATETIME) AS recent_start,
      CAST(ep.recent_end AS DATETIME) AS recent_end,
      CAST(ep.baseline_start AS DATETIME) AS baseline_start,
      CAST(ep.baseline_end AS DATETIME) AS baseline_end,
      
      -- Workdays (per employee - based on their specific period boundaries)
      ISNULL(wd.workdays_r, 0) AS workdays_r,
      ISNULL(wd.workdays_b, 0) AS workdays_b,
      
      -- Presence counts
      ISNULL(p.presence_r, 0) AS presence_r,
      ISNULL(p.presence_b, 0) AS presence_b,
      
      -- Presence percentages (as FLOAT, not formatted string)
      CASE 
        WHEN ISNULL(wd.workdays_r, 0) > 0 
        THEN CAST(ISNULL(p.presence_r, 0) AS FLOAT) / CAST(wd.workdays_r AS FLOAT)
        ELSE 0.0
      END AS presence_pct_r,
      CASE 
        WHEN ISNULL(wd.workdays_b, 0) > 0 
        THEN CAST(ISNULL(p.presence_b, 0) AS FLOAT) / CAST(wd.workdays_b AS FLOAT)
        ELSE 0.0
      END AS presence_pct_b,
      
      -- Non-workday presence
      ISNULL(p.non_workday_presence_r, 0) AS non_workday_presence_r,
      ISNULL(p.non_workday_presence_b, 0) AS non_workday_presence_b,
      
      -- Time metrics
      ISNULL(tm.avg_minutes_r, 0.0) AS avg_minutes_r,
      ISNULL(tm.avg_minutes_b, 0.0) AS avg_minutes_b,
      ISNULL(tm.avg_arrival_r, CAST('00:00:00' AS TIME)) AS avg_arrival_r,
      ISNULL(tm.avg_arrival_b, CAST('00:00:00' AS TIME)) AS avg_arrival_b,
      ISNULL(tm.avg_departure_r, CAST('00:00:00' AS TIME)) AS avg_departure_r,
      ISNULL(tm.avg_departure_b, CAST('00:00:00' AS TIME)) AS avg_departure_b,
      
      -- Absence (workdays - presence)
      ISNULL(wd.workdays_r, 0) - ISNULL(p.presence_r, 0) AS absence_r,
      ISNULL(wd.workdays_b, 0) - ISNULL(p.presence_b, 0) AS absence_b,
      
      -- Absence percentages
      CASE 
        WHEN ISNULL(wd.workdays_r, 0) > 0 
        THEN CAST((ISNULL(wd.workdays_r, 0) - ISNULL(p.presence_r, 0)) AS FLOAT) / CAST(wd.workdays_r AS FLOAT)
        ELSE 0.0
      END AS absence_pct_r,
      CASE 
        WHEN ISNULL(wd.workdays_b, 0) > 0 
        THEN CAST((ISNULL(wd.workdays_b, 0) - ISNULL(p.presence_b, 0)) AS FLOAT) / CAST(wd.workdays_b AS FLOAT)
        ELSE 0.0
      END AS absence_pct_b
      
    INTO #final_metrics
    FROM #emp_periods ep
    LEFT JOIN #workdays wd
      ON wd.client_id = ep.client_id
      AND wd.emp_id = ep.emp_id
    LEFT JOIN #presence p
      ON p.client_id = ep.client_id
      AND p.emp_id = ep.emp_id
    LEFT JOIN #time_metrics tm
      ON tm.client_id = ep.client_id
      AND tm.emp_id = ep.emp_id;
    
    -- ========================================================================
    -- STEP 11: INSERT INTO calc_period_metrics TABLE
    -- ========================================================================
    
    INSERT INTO dbo.calc_period_metrics
    (
      client_id, emp_id,
      recent_start, recent_end, baseline_start, baseline_end,
      workdays_r, workdays_b,
      presence_r, presence_b,
      presence_pct_r, presence_pct_b,
      avg_minutes_r, avg_minutes_b,
      avg_arrival_r, avg_arrival_b,
      avg_departure_r, avg_departure_b,
      absence_r, absence_b,
      absence_pct_r, absence_pct_b,
      non_workday_presence_r, non_workday_presence_b
    )
    SELECT 
      client_id, emp_id,
      recent_start, recent_end, baseline_start, baseline_end,
      workdays_r, workdays_b,
      presence_r, presence_b,
      presence_pct_r, presence_pct_b,
      avg_minutes_r, avg_minutes_b,
      avg_arrival_r, avg_arrival_b,
      avg_departure_r, avg_departure_b,
      absence_r, absence_b,
      absence_pct_r, absence_pct_b,
      non_workday_presence_r, non_workday_presence_b
    FROM #final_metrics;
    
    -- ========================================================================
    -- STEP 12: ALSO POPULATE calculated_data TABLE (for backward compatibility)
    -- ========================================================================
    
    DELETE FROM dbo.calculated_data WHERE client_id=@client_id;
    
    INSERT INTO dbo.calculated_data
    (
      client_id, emp_id, department, emp_role, site_name,
      baseline_start, baseline_end, baseline_days,
      recent_start, recent_end, recent_days,
      pres_b, pres_r, pres_b_norm, pres_r_norm,
      max_off_run, short_gap_count_r,
      long_r, late_r,
      avg_min_b, avg_min_r,
      odd_pct_r, door_mis_pct_r, pingpong_pct_r,
      pres_b_norm_adj, pres_r_norm_adj,
      max_off_run_adj, short_gap_count_r_adj
    )
    SELECT
      cpm.client_id,
      cpm.emp_id,
      ISNULL(vd.department, N'Not Reported') AS department,
      ISNULL(vr.emp_role, N'Not Reported') AS emp_role,
      ISNULL(vs.site_name, N'') AS site_name,
      CAST(cpm.baseline_start AS DATE) AS baseline_start,
      CAST(cpm.baseline_end AS DATE) AS baseline_end,
      cpm.workdays_b AS baseline_days,
      CAST(cpm.recent_start AS DATE) AS recent_start,
      CAST(cpm.recent_end AS DATE) AS recent_end,
      cpm.workdays_r AS recent_days,
      cpm.presence_b AS pres_b,
      cpm.presence_r AS pres_r,
      cpm.presence_pct_b AS pres_b_norm,
      cpm.presence_pct_r AS pres_r_norm,
      0 AS max_off_run,  -- Not calculated in period-based approach, set to 0
      0 AS short_gap_count_r,  -- Not calculated in period-based approach, set to 0
      0.0 AS long_r,  -- Not calculated in period-based approach, set to 0
      0.0 AS late_r,  -- Not calculated in period-based approach, set to 0
      cpm.avg_minutes_b AS avg_min_b,
      cpm.avg_minutes_r AS avg_min_r,
      0.0 AS odd_pct_r,  -- Not calculated in period-based approach, set to 0
      0.0 AS door_mis_pct_r,  -- Not calculated in period-based approach, set to 0
      0.0 AS pingpong_pct_r,  -- Not calculated in period-based approach, set to 0
      NULL AS pres_b_norm_adj,  -- Will be updated by usp_update_adjusted_metrics
      NULL AS pres_r_norm_adj,  -- Will be updated by usp_update_adjusted_metrics
      NULL AS max_off_run_adj,  -- Will be updated by usp_update_adjusted_metrics
      NULL AS short_gap_count_r_adj  -- Will be updated by usp_update_adjusted_metrics
    FROM dbo.calc_period_metrics cpm
    LEFT JOIN dbo.v_client_emp_department vd ON vd.client_id = cpm.client_id AND vd.emp_id = cpm.emp_id
    LEFT JOIN dbo.v_client_emp_role vr ON vr.client_id = cpm.client_id AND vr.emp_id = cpm.emp_id
    LEFT JOIN dbo.v_client_emp_site vs ON vs.client_id = cpm.client_id AND vs.emp_id = cpm.emp_id
    WHERE cpm.client_id = @client_id;
    
    -- ========================================================================
    -- STEP 13: VALIDATE RESULTS AND COMMIT
    -- ========================================================================
    
    IF NOT EXISTS (SELECT 1 FROM dbo.calc_period_metrics WHERE client_id = @client_id)
    BEGIN
      RAISERROR('usp_calc_periods: No rows inserted into calc_period_metrics for client_id=%s. Check employee filter criteria.', 10, 1, @client_id);
    END
    
    IF NOT EXISTS (SELECT 1 FROM dbo.calculated_data WHERE client_id = @client_id)
    BEGIN
      RAISERROR('usp_calc_periods: No rows inserted into calculated_data for client_id=%s.', 10, 1, @client_id);
    END
    
    IF @TransactionCount = 0
      COMMIT TRANSACTION;
    
  END TRY
  BEGIN CATCH
    SELECT 
      @ErrorMessage = ERROR_MESSAGE(),
      @ErrorSeverity = ERROR_SEVERITY(),
      @ErrorState = ERROR_STATE();
    
    IF @TransactionCount = 0 AND @@TRANCOUNT > 0
      ROLLBACK TRANSACTION;
    
    RAISERROR(
      'usp_calc_periods: Error processing client_id=%s. Error: %s', 
      @ErrorSeverity, 
      @ErrorState,
      @client_id,
      @ErrorMessage
    );
    
    RETURN -1;
  END CATCH
  
END
GO

