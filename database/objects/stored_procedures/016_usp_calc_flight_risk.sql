
/****** Object:  StoredProcedure [dbo].[usp_calc_flight_risk]    Script Date: 22/12/2025 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_calc_flight_risk]
  @client_id NVARCHAR(50)
AS
BEGIN
  /*
  ================================================================================
  Procedure: usp_calc_flight_risk
  Purpose:   Calculate flight risk score for employees based on attendance pattern
             changes comparing baseline vs recent periods. Uses weighted scoring
             model with configurable thresholds.
  
  Parameters:
    @client_id - Client identifier (required)
  
  Returns:   None (inserts into report_flight table with risk_score)
  
  Multi-tenant: Yes - all operations filtered by @client_id
  Transaction:  Yes - wrapped with error handling
  ================================================================================
  */
  
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  
  -- Guard clause
  IF @client_id IS NULL OR LTRIM(RTRIM(@client_id)) = N''
  BEGIN
    RAISERROR('usp_calc_flight_risk: @client_id is required.', 16, 1);
    RETURN;
  END
  
  IF NOT EXISTS (SELECT 1 FROM dbo.calc_period_metrics WHERE client_id = @client_id)
  BEGIN
    RAISERROR('No rows in calc_period_metrics for client_id=%s.', 16, 1, @client_id);
    RETURN;
  END
  
  -- ========================================================================
  -- LOAD CONFIGURABLE PARAMETERS FROM risk_config TABLE
  -- ========================================================================
  
  -- Feature weights (should sum to 100, but we'll normalize if needed)
  DECLARE
    @w_attendance_decline FLOAT,
    @w_absence_increase FLOAT,
    @w_hours_decline FLOAT,
    @w_arrival_change FLOAT,
    @w_departure_change FLOAT,
    @w_non_workday_change FLOAT,
    @w_multi_factor_bonus FLOAT;
    
  -- Threshold multipliers
  DECLARE
    @attendance_threshold_critical FLOAT,  -- e.g., 0.30 for 30% decline
    @attendance_threshold_high FLOAT,      -- e.g., 0.20 for 20% decline
    @attendance_threshold_moderate FLOAT,  -- e.g., 0.10 for 10% decline
    @attendance_mult_critical FLOAT,       -- e.g., 1.5
    @attendance_mult_high FLOAT,           -- e.g., 1.3
    @attendance_mult_moderate FLOAT,       -- e.g., 1.1
    @absence_threshold_critical FLOAT,     -- e.g., 0.25 for 25% increase
    @absence_threshold_high FLOAT,         -- e.g., 0.15 for 15% increase
    @absence_mult_critical FLOAT,          -- e.g., 1.4
    @absence_mult_high FLOAT;              -- e.g., 1.2
    
  -- Multi-factor decline thresholds
  DECLARE
    @multi_factor_threshold_2 FLOAT,       -- e.g., 0.05 (5% change)
    @multi_factor_threshold_3 FLOAT,       -- e.g., 0.05
    @multi_factor_threshold_arrival_min INT, -- e.g., 15 minutes
    @multi_factor_threshold_departure_min INT, -- e.g., 15 minutes
    @multi_factor_bonus_4 FLOAT,           -- e.g., 5 points
    @multi_factor_bonus_3 FLOAT,           -- e.g., 3 points
    @multi_factor_bonus_2 FLOAT;           -- e.g., 1 point
    
  -- Risk level boundaries
  DECLARE
    @risk_threshold_low INT,               -- e.g., 25
    @risk_threshold_medium INT,            -- e.g., 50
    @risk_threshold_high INT;              -- e.g., 75
    
  -- Minimum data requirements
  DECLARE
    @min_baseline_days INT,                -- e.g., 14
    @min_recent_days INT;                  -- e.g., 7
    
  -- Helper function to get config with fallback
  -- Pattern: client-specific first, then global (client_id IS NULL), then default
  
  SELECT
    -- Feature weights (defaults sum to ~100)
    @w_attendance_decline = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_w_attendance_decline') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_w_attendance_decline') AS FLOAT), 35.0),
    @w_absence_increase = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_w_absence_increase') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_w_absence_increase') AS FLOAT), 20.0),
    @w_hours_decline = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_w_hours_decline') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_w_hours_decline') AS FLOAT), 15.0),
    @w_arrival_change = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_w_arrival_change') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_w_arrival_change') AS FLOAT), 10.0),
    @w_departure_change = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_w_departure_change') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_w_departure_change') AS FLOAT), 10.0),
    @w_non_workday_change = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_w_non_workday_change') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_w_non_workday_change') AS FLOAT), 5.0),
    @w_multi_factor_bonus = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_w_multi_factor_bonus') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_w_multi_factor_bonus') AS FLOAT), 5.0),
      
    -- Attendance threshold multipliers
    @attendance_threshold_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_attendance_threshold_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_attendance_threshold_critical') AS FLOAT), 0.30),
    @attendance_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_attendance_threshold_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_attendance_threshold_high') AS FLOAT), 0.20),
    @attendance_threshold_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_attendance_threshold_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_attendance_threshold_moderate') AS FLOAT), 0.10),
    @attendance_mult_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_attendance_mult_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_attendance_mult_critical') AS FLOAT), 1.5),
    @attendance_mult_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_attendance_mult_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_attendance_mult_high') AS FLOAT), 1.3),
    @attendance_mult_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_attendance_mult_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_attendance_mult_moderate') AS FLOAT), 1.1),
      
    -- Absence threshold multipliers
    @absence_threshold_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_absence_threshold_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_absence_threshold_critical') AS FLOAT), 0.25),
    @absence_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_absence_threshold_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_absence_threshold_high') AS FLOAT), 0.15),
    @absence_mult_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_absence_mult_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_absence_mult_critical') AS FLOAT), 1.4),
    @absence_mult_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_absence_mult_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_absence_mult_high') AS FLOAT), 1.2),
      
    -- Multi-factor decline thresholds
    @multi_factor_threshold_2 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_multi_factor_threshold_pct') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_multi_factor_threshold_pct') AS FLOAT), 0.05),
    @multi_factor_threshold_3 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_multi_factor_threshold_pct') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_multi_factor_threshold_pct') AS FLOAT), 0.05),
    @multi_factor_threshold_arrival_min = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_multi_factor_threshold_arrival_min') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_multi_factor_threshold_arrival_min') AS INT), 15),
    @multi_factor_threshold_departure_min = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_multi_factor_threshold_departure_min') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_multi_factor_threshold_departure_min') AS INT), 15),
    @multi_factor_bonus_4 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_multi_factor_bonus_4') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_multi_factor_bonus_4') AS FLOAT), 5.0),
    @multi_factor_bonus_3 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_multi_factor_bonus_3') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_multi_factor_bonus_3') AS FLOAT), 3.0),
    @multi_factor_bonus_2 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_multi_factor_bonus_2') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_multi_factor_bonus_2') AS FLOAT), 1.0),
      
    -- Risk level boundaries
    @risk_threshold_low = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_threshold_low') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_threshold_low') AS INT), 25),
    @risk_threshold_medium = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_threshold_medium') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_threshold_medium') AS INT), 50),
    @risk_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_threshold_high') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_threshold_high') AS INT), 75),
      
    -- Minimum data requirements
    @min_baseline_days = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_min_baseline_days') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_min_baseline_days') AS INT), 14),
    @min_recent_days = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_risk_min_recent_days') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='flight_risk_min_recent_days') AS INT), 7);
  
  -- Normalize weights (in case they don't sum to 100)
  DECLARE @weight_sum FLOAT = @w_attendance_decline + @w_absence_increase + @w_hours_decline + 
                               @w_arrival_change + @w_departure_change + @w_non_workday_change;
  IF @weight_sum > 0
  BEGIN
    SET @w_attendance_decline = @w_attendance_decline * 100.0 / @weight_sum;
    SET @w_absence_increase = @w_absence_increase * 100.0 / @weight_sum;
    SET @w_hours_decline = @w_hours_decline * 100.0 / @weight_sum;
    SET @w_arrival_change = @w_arrival_change * 100.0 / @weight_sum;
    SET @w_departure_change = @w_departure_change * 100.0 / @weight_sum;
    SET @w_non_workday_change = @w_non_workday_change * 100.0 / @weight_sum;
  END
  
  -- ========================================================================
  -- CLEAN OLD DATA
  -- ========================================================================
  
  DELETE FROM dbo.report_flight WHERE client_id=@client_id;
  
  -- ========================================================================
  -- CALCULATE FLIGHT RISK SCORES
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#risk_calc') IS NOT NULL DROP TABLE #risk_calc;
  
  SELECT
    cpm.client_id,
    cpm.emp_id,
    CAST(cpm.baseline_start AS DATE) AS baseline_start,
    CAST(cpm.baseline_end AS DATE) AS baseline_end,
    CAST(cpm.recent_start AS DATE) AS recent_start,
    CAST(cpm.recent_end AS DATE) AS recent_end,
    cpm.workdays_b,
    cpm.workdays_r,
    cpm.presence_pct_b,
    cpm.presence_pct_r,
    cpm.absence_pct_b,
    cpm.absence_pct_r,
    cpm.avg_minutes_b,
    cpm.avg_minutes_r,
    cpm.avg_arrival_b,
    cpm.avg_arrival_r,
    cpm.avg_departure_b,
    cpm.avg_departure_r,
    cpm.non_workday_presence_b,
    cpm.non_workday_presence_r,
    
    -- Calculate deltas
    CASE 
      WHEN cpm.presence_pct_b > 0 
      THEN (cpm.presence_pct_b - cpm.presence_pct_r) / cpm.presence_pct_b
      ELSE 0.0
    END AS presence_pct_delta,
    
    CASE 
      WHEN cpm.absence_pct_b > 0 
      THEN (cpm.absence_pct_r - cpm.absence_pct_b) / cpm.absence_pct_b
      WHEN cpm.absence_pct_r > 0 THEN 1.0  -- Increase from 0 to something
      ELSE 0.0
    END AS absence_pct_delta,
    
    CASE 
      WHEN cpm.avg_minutes_b > 0 
      THEN (cpm.avg_minutes_b - cpm.avg_minutes_r) / cpm.avg_minutes_b
      ELSE 0.0
    END AS avg_minutes_delta_pct,
    
    DATEDIFF(MINUTE, CAST(cpm.avg_arrival_b AS TIME), CAST(cpm.avg_arrival_r AS TIME)) AS arrival_delta_minutes,
    DATEDIFF(MINUTE, CAST(cpm.avg_departure_r AS TIME), CAST(cpm.avg_departure_b AS TIME)) AS departure_delta_minutes,
    
    CAST(cpm.non_workday_presence_r AS FLOAT) - CAST(cpm.non_workday_presence_b AS FLOAT) AS non_workday_delta
    
  INTO #risk_calc
  FROM dbo.calc_period_metrics cpm
  WHERE cpm.client_id = @client_id
    AND cpm.workdays_b >= @min_baseline_days
    AND cpm.workdays_r >= @min_recent_days;
  
  -- ========================================================================
  -- CALCULATE RISK SCORES
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#risk_scores') IS NOT NULL DROP TABLE #risk_scores;
  
  SELECT
    rc.*,
    
    -- 1. Attendance Decline Score (0 to @w_attendance_decline)
    CASE 
      WHEN rc.presence_pct_delta > 0 
      THEN CASE 
        WHEN rc.presence_pct_delta * @w_attendance_decline * 100.0 > @w_attendance_decline 
        THEN @w_attendance_decline
        ELSE rc.presence_pct_delta * @w_attendance_decline * 100.0
      END
      ELSE 0.0
    END AS attendance_risk_score,
    
    -- Attendance multiplier
    CASE 
      WHEN rc.presence_pct_delta > @attendance_threshold_critical THEN @attendance_mult_critical
      WHEN rc.presence_pct_delta > @attendance_threshold_high THEN @attendance_mult_high
      WHEN rc.presence_pct_delta > @attendance_threshold_moderate THEN @attendance_mult_moderate
      ELSE 1.0
    END AS attendance_multiplier,
    
    -- 2. Absence Increase Score (0 to @w_absence_increase)
    CASE 
      WHEN rc.absence_pct_delta > 0 
      THEN CASE
        WHEN rc.absence_pct_delta * @w_absence_increase * 100.0 > @w_absence_increase
        THEN @w_absence_increase
        ELSE rc.absence_pct_delta * @w_absence_increase * 100.0
      END
      ELSE 0.0
    END AS absence_risk_score,
    
    -- Absence multiplier
    CASE 
      WHEN rc.absence_pct_delta > @absence_threshold_critical THEN @absence_mult_critical
      WHEN rc.absence_pct_delta > @absence_threshold_high THEN @absence_mult_high
      ELSE 1.0
    END AS absence_multiplier,
    
    -- 3. Hours Decline Score (0 to @w_hours_decline)
    CASE 
      WHEN rc.avg_minutes_delta_pct > 0 
      THEN CASE
        WHEN rc.avg_minutes_delta_pct * @w_hours_decline * 100.0 > @w_hours_decline
        THEN @w_hours_decline
        ELSE rc.avg_minutes_delta_pct * @w_hours_decline * 100.0
      END
      ELSE 0.0
    END AS hours_risk_score,
    
    -- 4. Arrival Time Change Score (0 to @w_arrival_change)
    CASE 
      WHEN rc.arrival_delta_minutes > 0  -- Later arrival
      THEN CASE
        WHEN (rc.arrival_delta_minutes / 60.0) * @w_arrival_change > @w_arrival_change
        THEN @w_arrival_change
        ELSE (rc.arrival_delta_minutes / 60.0) * @w_arrival_change
      END
      ELSE 0.0
    END AS arrival_risk_score,
    
    -- 5. Departure Time Change Score (0 to @w_departure_change)
    CASE 
      WHEN rc.departure_delta_minutes > 0  -- Earlier departure
      THEN CASE
        WHEN (rc.departure_delta_minutes / 60.0) * @w_departure_change > @w_departure_change
        THEN @w_departure_change
        ELSE (rc.departure_delta_minutes / 60.0) * @w_departure_change
      END
      ELSE 0.0
    END AS departure_risk_score,
    
    -- 6. Non-Workday Presence Change Score (0 to @w_non_workday_change)
    CASE 
      WHEN ABS(rc.non_workday_delta) > 0
      THEN CASE
        WHEN ABS(rc.non_workday_delta) / 5.0 * @w_non_workday_change > @w_non_workday_change
        THEN @w_non_workday_change
        ELSE ABS(rc.non_workday_delta) / 5.0 * @w_non_workday_change
      END
      ELSE 0.0
    END AS non_workday_risk_score,
    
    -- Count declining factors for multi-factor bonus
    CASE WHEN rc.presence_pct_delta > @multi_factor_threshold_2 THEN 1 ELSE 0 END +
    CASE WHEN rc.avg_minutes_delta_pct > @multi_factor_threshold_3 THEN 1 ELSE 0 END +
    CASE WHEN rc.arrival_delta_minutes > @multi_factor_threshold_arrival_min THEN 1 ELSE 0 END +
    CASE WHEN rc.departure_delta_minutes > @multi_factor_threshold_departure_min THEN 1 ELSE 0 END AS declining_factors
    
  INTO #risk_scores
  FROM #risk_calc rc;
  
  -- ========================================================================
  -- CALCULATE FINAL RISK SCORES WITH MULTIPLIERS AND BONUSES
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#final_risk') IS NOT NULL DROP TABLE #final_risk;
  
  SELECT
    rs.*,
    
    -- Multi-factor bonus
    CASE
      WHEN rs.declining_factors >= 4 THEN @multi_factor_bonus_4
      WHEN rs.declining_factors >= 3 THEN @multi_factor_bonus_3
      WHEN rs.declining_factors >= 2 THEN @multi_factor_bonus_2
      ELSE 0.0
    END AS multi_factor_bonus,
    
    -- Base score with multipliers
    (rs.attendance_risk_score * rs.attendance_multiplier) +
    (rs.absence_risk_score * rs.absence_multiplier) +
    rs.hours_risk_score +
    rs.arrival_risk_score +
    rs.departure_risk_score +
    rs.non_workday_risk_score AS base_score
    
  INTO #final_risk
  FROM #risk_scores rs;
  
  -- ========================================================================
  -- INSERT INTO report_flight TABLE
  -- ========================================================================
  
  INSERT INTO dbo.report_flight
  (
    client_id,
    emp_id,
    department,
    emp_role,
    site_name,
    risk_score,
    risk_type,
    score_explanation,
    computed_at
  )
  SELECT
    fr.client_id,
    fr.emp_id,
    ISNULL(vd.department, N'Not Reported') AS department,
    ISNULL(vr.emp_role, N'Not Reported') AS emp_role,
    ISNULL(vs.site_name, N'') AS site_name,
    CASE 
      WHEN CAST(fr.base_score + fr.multi_factor_bonus AS INT) > 100 THEN 100
      ELSE CAST(fr.base_score + fr.multi_factor_bonus AS INT)
    END AS risk_score,
    CASE
      WHEN fr.base_score + fr.multi_factor_bonus >= @risk_threshold_high THEN N'Critical Risk'
      WHEN fr.base_score + fr.multi_factor_bonus >= @risk_threshold_medium THEN N'High Risk'
      WHEN fr.base_score + fr.multi_factor_bonus >= @risk_threshold_low THEN N'Medium Risk'
      ELSE N'Low Risk'
    END AS risk_type,
    CONCAT(
      N'Attendance: ', CAST(CAST(fr.attendance_risk_score * fr.attendance_multiplier AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Absence: ', CAST(CAST(fr.absence_risk_score * fr.absence_multiplier AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Hours: ', CAST(CAST(fr.hours_risk_score AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Arrival: ', CAST(CAST(fr.arrival_risk_score AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Departure: ', CAST(CAST(fr.departure_risk_score AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Non-workday: ', CAST(CAST(fr.non_workday_risk_score AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Multi-factor bonus: ', CAST(CAST(fr.multi_factor_bonus AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts'
    ) AS score_explanation,
    SYSUTCDATETIME() AS computed_at
  FROM #final_risk fr
  LEFT JOIN dbo.v_client_emp_department vd ON vd.client_id = fr.client_id AND vd.emp_id = fr.emp_id
  LEFT JOIN dbo.v_client_emp_role vr ON vr.client_id = fr.client_id AND vr.emp_id = fr.emp_id
  LEFT JOIN dbo.v_client_emp_site vs ON vs.client_id = fr.client_id AND vs.emp_id = fr.emp_id;
  
  -- ========================================================================
  -- VALIDATION
  -- ========================================================================
  
  IF @@ROWCOUNT = 0
  BEGIN
    RAISERROR('usp_calc_flight_risk: No rows inserted into report_flight for client_id=%s. Check minimum data requirements.', 10, 1, @client_id);
  END
  
END
GO

