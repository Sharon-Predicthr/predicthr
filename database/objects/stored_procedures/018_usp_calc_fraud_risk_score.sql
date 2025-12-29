
/****** Object:  StoredProcedure [dbo].[usp_calc_fraud_risk_score]    Script Date: 22/12/2025 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_calc_fraud_risk_score]
  @client_id NVARCHAR(50)
AS
BEGIN
  /*
  ================================================================================
  Procedure: usp_calc_fraud_risk_score
  Purpose:   Calculate fraud/integrity risk score for employees based on
             statistical anomaly detection comparing individual patterns to peer
             group norms. Uses Z-score based percentile ranking with weighted
             composite scoring.
  
  Parameters:
    @client_id - Client identifier (required)
  
  Returns:   None (inserts into calc_fraud_metrics and report_fraud tables)
  
  Multi-tenant: Yes - all operations filtered by @client_id
  Transaction:  Yes - wrapped with error handling
  ================================================================================
  */
  
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  
  -- Guard clause
  IF @client_id IS NULL OR LTRIM(RTRIM(@client_id)) = N''
  BEGIN
    RAISERROR('usp_calc_fraud_risk_score: @client_id is required.', 16, 1);
    RETURN;
  END
  
  IF NOT EXISTS (SELECT 1 FROM dbo.calculated_data WHERE client_id = @client_id)
  BEGIN
    RAISERROR('No rows in calculated_data for client_id=%s.', 16, 1, @client_id);
    RETURN;
  END
  
  -- ========================================================================
  -- LOAD CONFIGURABLE PARAMETERS FROM risk_config TABLE
  -- ========================================================================
  
  DECLARE
    @w_door_mismatch FLOAT,
    @w_pingpong FLOAT,
    @w_odd_hours FLOAT,
    @w_session_length FLOAT,
    @w_sessions_per_day FLOAT,
    @w_multi_factor_bonus FLOAT,
    @min_peer_group_size INT,
    @min_days_analyzed INT,
    @multi_factor_threshold_percentile FLOAT,
    @multi_factor_bonus_3 FLOAT,
    @multi_factor_bonus_2 FLOAT,
    @risk_threshold_low INT,
    @risk_threshold_medium INT,
    @risk_threshold_high INT;
    
  SELECT
    @w_door_mismatch = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_w_door_mismatch') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_w_door_mismatch') AS FLOAT), 35.0),
    @w_pingpong = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_w_pingpong') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_w_pingpong') AS FLOAT), 25.0),
    @w_odd_hours = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_w_odd_hours') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_w_odd_hours') AS FLOAT), 15.0),
    @w_session_length = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_w_session_length') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_w_session_length') AS FLOAT), 10.0),
    @w_sessions_per_day = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_w_sessions_per_day') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_w_sessions_per_day') AS FLOAT), 10.0),
    @w_multi_factor_bonus = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_w_multi_factor_bonus') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_w_multi_factor_bonus') AS FLOAT), 5.0),
    @min_peer_group_size = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_min_peer_group_size') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_min_peer_group_size') AS INT), 5),
    @min_days_analyzed = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_min_days_analyzed') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_min_days_analyzed') AS INT), 5),
    @multi_factor_threshold_percentile = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_multi_factor_threshold_percentile') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_multi_factor_threshold_percentile') AS FLOAT), 90.0),
    @multi_factor_bonus_3 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_multi_factor_bonus_3') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_multi_factor_bonus_3') AS FLOAT), 5.0),
    @multi_factor_bonus_2 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_multi_factor_bonus_2') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_multi_factor_bonus_2') AS FLOAT), 3.0),
    @risk_threshold_low = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_threshold_low') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_threshold_low') AS INT), 40),
    @risk_threshold_medium = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_threshold_medium') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_threshold_medium') AS INT), 60),
    @risk_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='fraud_risk_threshold_high') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='fraud_risk_threshold_high') AS INT), 80);
  
  -- Normalize weights
  DECLARE @weight_sum FLOAT = @w_door_mismatch + @w_pingpong + @w_odd_hours + 
                               @w_session_length + @w_sessions_per_day;
  IF @weight_sum > 0
  BEGIN
    SET @w_door_mismatch = @w_door_mismatch * 100.0 / @weight_sum;
    SET @w_pingpong = @w_pingpong * 100.0 / @weight_sum;
    SET @w_odd_hours = @w_odd_hours * 100.0 / @weight_sum;
    SET @w_session_length = @w_session_length * 100.0 / @weight_sum;
    SET @w_sessions_per_day = @w_sessions_per_day * 100.0 / @weight_sum;
  END
  
  -- ========================================================================
  -- GET ANALYSIS PERIOD (use recent period from calculated_data)
  -- ========================================================================
  
  DECLARE @analysis_start DATE, @analysis_end DATE;
  
  SELECT TOP(1) 
    @analysis_start = recent_start,
    @analysis_end = recent_end
  FROM dbo.calculated_data
  WHERE client_id = @client_id
  ORDER BY recent_start;
  
  -- ========================================================================
  -- STEP 1: CALCULATE EMPLOYEE-LEVEL METRICS
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#emp_metrics') IS NOT NULL DROP TABLE #emp_metrics;
  
  -- Get metrics from calculated_data and calculate additional metrics
  -- Note: emp_sessions only has first/last per day, so we use attendance table for session counts
  SELECT
    cd.client_id,
    cd.emp_id,
    ISNULL(vd.department, N'Not Reported') AS department,
    ISNULL(vr.emp_role, N'Not Reported') AS emp_role,
    cd.recent_start AS analysis_period_start,
    cd.recent_end AS analysis_period_end,
    cd.recent_days AS days_analyzed,
    -- Metrics from calculated_data
    ISNULL(cd.door_mis_pct_r, 0.0) AS door_mismatch_pct,
    ISNULL(cd.pingpong_pct_r, 0.0) AS pingpong_pct,
    ISNULL(cd.odd_pct_r, 0.0) AS odd_hours_pct,
    -- Calculate average session length from emp_sessions (this is valid - it's the daily session length)
    CASE 
      WHEN COUNT(DISTINCT CAST(es.session_start AS DATE)) > 0
      THEN AVG(CAST(es.minutes_worked AS FLOAT))
      ELSE 0.0
    END AS avg_session_minutes,
    -- Calculate average sessions per day from attendance table (all punches per day)
    CASE 
      WHEN COUNT(DISTINCT CAST(a.event_date AS DATE)) > 0
      THEN CAST(COUNT(DISTINCT CAST(a.event_date AS DATE)) AS FLOAT) / COUNT(DISTINCT CAST(a.event_date AS DATE))
     ELSE 0.0
    END AS avg_sessions_per_day
  INTO #emp_metrics
  FROM dbo.calculated_data cd
  LEFT JOIN dbo.v_client_emp_department vd ON vd.client_id = cd.client_id AND vd.emp_id = cd.emp_id
  LEFT JOIN dbo.v_client_emp_role vr ON vr.client_id = cd.client_id AND vr.emp_id = cd.emp_id
  LEFT JOIN dbo.emp_sessions es ON es.client_id = cd.client_id 
    AND es.emp_id = cd.emp_id
    AND CAST(es.session_start AS DATE) BETWEEN cd.recent_start AND cd.recent_end
  LEFT JOIN dbo.attendance a ON a.client_id = cd.client_id
    AND a.emp_id = cd.emp_id
    AND a.event_date BETWEEN cd.recent_start AND cd.recent_end
  WHERE cd.client_id = @client_id
    AND cd.recent_days >= @min_days_analyzed
  GROUP BY 
    cd.client_id, cd.emp_id, vd.department, vr.emp_role,
    cd.recent_start, cd.recent_end, cd.recent_days,
    cd.door_mis_pct_r, cd.pingpong_pct_r, cd.odd_pct_r;
  
  -- ========================================================================
  -- STEP 2: CALCULATE PEER GROUP STATISTICS
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#peer_stats') IS NOT NULL DROP TABLE #peer_stats;
  
  -- Calculate peer group statistics by department+role (primary)
  -- Fall back to department-only if peer group too small
  WITH peer_groups AS (
    SELECT
      em.client_id,
      em.emp_id,
      em.department,
      em.emp_role,
      -- Try department+role peer group first
      COUNT(*) OVER (PARTITION BY em.department, em.emp_role) AS peer_group_size_dept_role,
      -- Department-only peer group (fallback)
      COUNT(*) OVER (PARTITION BY em.department) AS peer_group_size_dept,
      -- Client-wide peer group (last resort)
      COUNT(*) OVER () AS peer_group_size_client,
      -- Means by department+role
      AVG(em.door_mismatch_pct) OVER (PARTITION BY em.department, em.emp_role) AS mean_door_mismatch_dept_role,
      AVG(em.pingpong_pct) OVER (PARTITION BY em.department, em.emp_role) AS mean_pingpong_dept_role,
      AVG(em.odd_hours_pct) OVER (PARTITION BY em.department, em.emp_role) AS mean_odd_hours_dept_role,
      AVG(em.avg_session_minutes) OVER (PARTITION BY em.department, em.emp_role) AS mean_session_length_dept_role,
      AVG(em.avg_sessions_per_day) OVER (PARTITION BY em.department, em.emp_role) AS mean_sessions_per_day_dept_role,
      -- StDev by department+role
      STDEV(em.door_mismatch_pct) OVER (PARTITION BY em.department, em.emp_role) AS std_door_mismatch_dept_role,
      STDEV(em.pingpong_pct) OVER (PARTITION BY em.department, em.emp_role) AS std_pingpong_dept_role,
      STDEV(em.odd_hours_pct) OVER (PARTITION BY em.department, em.emp_role) AS std_odd_hours_dept_role,
      STDEV(em.avg_session_minutes) OVER (PARTITION BY em.department, em.emp_role) AS std_session_length_dept_role,
      STDEV(em.avg_sessions_per_day) OVER (PARTITION BY em.department, em.emp_role) AS std_sessions_per_day_dept_role,
      -- Means by department (fallback)
      AVG(em.door_mismatch_pct) OVER (PARTITION BY em.department) AS mean_door_mismatch_dept,
      AVG(em.pingpong_pct) OVER (PARTITION BY em.department) AS mean_pingpong_dept,
      AVG(em.odd_hours_pct) OVER (PARTITION BY em.department) AS mean_odd_hours_dept,
      AVG(em.avg_session_minutes) OVER (PARTITION BY em.department) AS mean_session_length_dept,
      AVG(em.avg_sessions_per_day) OVER (PARTITION BY em.department) AS mean_sessions_per_day_dept,
      -- StDev by department (fallback)
      STDEV(em.door_mismatch_pct) OVER (PARTITION BY em.department) AS std_door_mismatch_dept,
      STDEV(em.pingpong_pct) OVER (PARTITION BY em.department) AS std_pingpong_dept,
      STDEV(em.odd_hours_pct) OVER (PARTITION BY em.department) AS std_odd_hours_dept,
      STDEV(em.avg_session_minutes) OVER (PARTITION BY em.department) AS std_session_length_dept,
      STDEV(em.avg_sessions_per_day) OVER (PARTITION BY em.department) AS std_sessions_per_day_dept,
      -- Means client-wide (last resort)
      AVG(em.door_mismatch_pct) OVER () AS mean_door_mismatch_client,
      AVG(em.pingpong_pct) OVER () AS mean_pingpong_client,
      AVG(em.odd_hours_pct) OVER () AS mean_odd_hours_client,
      AVG(em.avg_session_minutes) OVER () AS mean_session_length_client,
      AVG(em.avg_sessions_per_day) OVER () AS mean_sessions_per_day_client,
      -- StDev client-wide (last resort)
      STDEV(em.door_mismatch_pct) OVER () AS std_door_mismatch_client,
      STDEV(em.pingpong_pct) OVER () AS std_pingpong_client,
      STDEV(em.odd_hours_pct) OVER () AS std_odd_hours_client,
      STDEV(em.avg_session_minutes) OVER () AS std_session_length_client,
      STDEV(em.avg_sessions_per_day) OVER () AS std_sessions_per_day_client
    FROM #emp_metrics em
  )
  SELECT
    client_id, emp_id, department, emp_role,
    -- Select peer group based on size (prefer department+role, fall back to department, then client-wide)
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN peer_group_size_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN peer_group_size_dept
      ELSE peer_group_size_client
    END AS peer_group_size,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN N'dept_role'
      WHEN peer_group_size_dept >= @min_peer_group_size THEN N'dept_only'
      ELSE N'client_wide'
    END AS peer_group_type,
    -- Select means based on peer group selection
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN mean_door_mismatch_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN mean_door_mismatch_dept
      ELSE mean_door_mismatch_client
    END AS peer_mean_door_mismatch,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN mean_pingpong_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN mean_pingpong_dept
      ELSE mean_pingpong_client
    END AS peer_mean_pingpong,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN mean_odd_hours_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN mean_odd_hours_dept
      ELSE mean_odd_hours_client
    END AS peer_mean_odd_hours,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN mean_session_length_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN mean_session_length_dept
      ELSE mean_session_length_client
    END AS peer_mean_session_length,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN mean_sessions_per_day_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN mean_sessions_per_day_dept
      ELSE mean_sessions_per_day_client
    END AS peer_mean_sessions_per_day,
    -- Select std devs based on peer group selection
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN std_door_mismatch_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN std_door_mismatch_dept
      ELSE std_door_mismatch_client
    END AS peer_std_door_mismatch,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN std_pingpong_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN std_pingpong_dept
      ELSE std_pingpong_client
    END AS peer_std_pingpong,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN std_odd_hours_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN std_odd_hours_dept
      ELSE std_odd_hours_client
    END AS peer_std_odd_hours,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN std_session_length_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN std_session_length_dept
      ELSE std_session_length_client
    END AS peer_std_session_length,
    CASE 
      WHEN peer_group_size_dept_role >= @min_peer_group_size THEN std_sessions_per_day_dept_role
      WHEN peer_group_size_dept >= @min_peer_group_size THEN std_sessions_per_day_dept
      ELSE std_sessions_per_day_client
    END AS peer_std_sessions_per_day
  INTO #peer_stats
  FROM peer_groups;
  
  -- ========================================================================
  -- STEP 3: CALCULATE Z-SCORES AND PERCENTILES
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#fraud_scores') IS NOT NULL DROP TABLE #fraud_scores;
  
  SELECT
    em.*,
    ps.peer_group_size,
    ps.peer_group_type,
    ps.peer_mean_door_mismatch,
    ps.peer_mean_pingpong,
    ps.peer_mean_odd_hours,
    ps.peer_mean_session_length,
    ps.peer_mean_sessions_per_day,
    -- Calculate Z-scores (handle division by zero)
    CASE 
      WHEN ps.peer_std_door_mismatch > 0 
      THEN (em.door_mismatch_pct - ps.peer_mean_door_mismatch) / ps.peer_std_door_mismatch
      ELSE 0.0
    END AS door_mismatch_zscore,
    CASE 
      WHEN ps.peer_std_pingpong > 0 
      THEN (em.pingpong_pct - ps.peer_mean_pingpong) / ps.peer_std_pingpong
      ELSE 0.0
    END AS pingpong_zscore,
    CASE 
      WHEN ps.peer_std_odd_hours > 0 
      THEN (em.odd_hours_pct - ps.peer_mean_odd_hours) / ps.peer_std_odd_hours
      ELSE 0.0
    END AS odd_hours_zscore,
    CASE 
      WHEN ps.peer_std_session_length > 0 
      THEN (em.avg_session_minutes - ps.peer_mean_session_length) / ps.peer_std_session_length
      ELSE 0.0
    END AS session_length_zscore,
    CASE 
      WHEN ps.peer_std_sessions_per_day > 0 
      THEN (em.avg_sessions_per_day - ps.peer_mean_sessions_per_day) / ps.peer_std_sessions_per_day
      ELSE 0.0
    END AS sessions_per_day_zscore
  INTO #fraud_scores
  FROM #emp_metrics em
  JOIN #peer_stats ps ON ps.client_id = em.client_id AND ps.emp_id = em.emp_id;
  
  -- Add percentile and score columns to temp table
  ALTER TABLE #fraud_scores ADD door_mismatch_percentile FLOAT;
  ALTER TABLE #fraud_scores ADD pingpong_percentile FLOAT;
  ALTER TABLE #fraud_scores ADD odd_hours_percentile FLOAT;
  ALTER TABLE #fraud_scores ADD session_length_percentile FLOAT;
  ALTER TABLE #fraud_scores ADD sessions_per_day_percentile FLOAT;
  ALTER TABLE #fraud_scores ADD fraud_risk_score INT;
  
  -- Calculate percentiles from Z-scores (approximation: 50 + z*20, capped at 0-100)
  -- Note: Only positive Z-scores indicate fraud risk (above average)
  UPDATE fs
  SET 
    door_mismatch_percentile = CASE 
      WHEN fs.door_mismatch_zscore > 0 THEN CASE WHEN 50 + (fs.door_mismatch_zscore * 20) > 100 THEN 100 ELSE 50 + (fs.door_mismatch_zscore * 20) END
      ELSE 0.0
    END,
    pingpong_percentile = CASE 
      WHEN fs.pingpong_zscore > 0 THEN CASE WHEN 50 + (fs.pingpong_zscore * 20) > 100 THEN 100 ELSE 50 + (fs.pingpong_zscore * 20) END
      ELSE 0.0
    END,
    odd_hours_percentile = CASE 
      WHEN fs.odd_hours_zscore > 0 THEN CASE WHEN 50 + (fs.odd_hours_zscore * 20) > 100 THEN 100 ELSE 50 + (fs.odd_hours_zscore * 20) END
      ELSE 0.0
    END,
    session_length_percentile = CASE 
      WHEN fs.session_length_zscore > 0 THEN CASE WHEN 50 + (fs.session_length_zscore * 20) > 100 THEN 100 ELSE 50 + (fs.session_length_zscore * 20) END
      WHEN fs.session_length_zscore < -2 THEN 100  -- Very short sessions are also suspicious
      ELSE 0.0
    END,
    sessions_per_day_percentile = CASE 
      WHEN fs.sessions_per_day_zscore > 0 THEN CASE WHEN 50 + (fs.sessions_per_day_zscore * 20) > 100 THEN 100 ELSE 50 + (fs.sessions_per_day_zscore * 20) END
      ELSE 0.0
    END
  FROM #fraud_scores fs;
  
  -- ========================================================================
  -- STEP 4: CALCULATE COMPOSITE FRAUD RISK SCORE
  -- ========================================================================
  
  UPDATE fs
  SET fraud_risk_score = CAST(ROUND(
    (fs.door_mismatch_percentile * @w_door_mismatch / 100.0) +
    (fs.pingpong_percentile * @w_pingpong / 100.0) +
    (fs.odd_hours_percentile * @w_odd_hours / 100.0) +
    (fs.session_length_percentile * @w_session_length / 100.0) +
    (fs.sessions_per_day_percentile * @w_sessions_per_day / 100.0) +
    -- Multi-factor bonus
    CASE 
      WHEN fs.door_mismatch_percentile >= @multi_factor_threshold_percentile AND
           fs.pingpong_percentile >= @multi_factor_threshold_percentile AND
           fs.odd_hours_percentile >= @multi_factor_threshold_percentile
      THEN @multi_factor_bonus_3
      WHEN (CASE WHEN fs.door_mismatch_percentile >= @multi_factor_threshold_percentile THEN 1 ELSE 0 END +
            CASE WHEN fs.pingpong_percentile >= @multi_factor_threshold_percentile THEN 1 ELSE 0 END +
            CASE WHEN fs.odd_hours_percentile >= @multi_factor_threshold_percentile THEN 1 ELSE 0 END) >= 2
      THEN @multi_factor_bonus_2
      ELSE 0.0
    END, 0) AS INT)
  FROM #fraud_scores fs;
  
  -- Cap scores at 100
  UPDATE #fraud_scores SET fraud_risk_score = CASE WHEN fraud_risk_score > 100 THEN 100 ELSE fraud_risk_score END;
  
  -- ========================================================================
  -- STEP 5: INSERT INTO calc_fraud_metrics TABLE
  -- ========================================================================
  
  DELETE FROM dbo.calc_fraud_metrics WHERE client_id = @client_id;
  
  INSERT INTO dbo.calc_fraud_metrics
  (
    client_id, emp_id, department, emp_role,
    analysis_period_start, analysis_period_end, days_analyzed,
    door_mismatch_pct, pingpong_pct, odd_hours_pct,
    avg_session_minutes, avg_sessions_per_day,
    peer_group_size, peer_group_type,
    peer_mean_door_mismatch, peer_mean_pingpong, peer_mean_odd_hours,
    peer_mean_session_length, peer_mean_sessions_per_day,
    door_mismatch_zscore, pingpong_zscore, odd_hours_zscore,
    session_length_zscore, sessions_per_day_zscore,
    door_mismatch_percentile, pingpong_percentile, odd_hours_percentile,
    session_length_percentile, sessions_per_day_percentile,
    fraud_risk_score, computed_at
  )
  SELECT
    fs.client_id, fs.emp_id, fs.department, fs.emp_role,
    fs.analysis_period_start, fs.analysis_period_end, fs.days_analyzed,
    fs.door_mismatch_pct, fs.pingpong_pct, fs.odd_hours_pct,
    fs.avg_session_minutes, fs.avg_sessions_per_day,
    fs.peer_group_size, fs.peer_group_type,
    fs.peer_mean_door_mismatch, fs.peer_mean_pingpong, fs.peer_mean_odd_hours,
    fs.peer_mean_session_length, fs.peer_mean_sessions_per_day,
    fs.door_mismatch_zscore, fs.pingpong_zscore, fs.odd_hours_zscore,
    fs.session_length_zscore, fs.sessions_per_day_zscore,
    fs.door_mismatch_percentile, fs.pingpong_percentile, fs.odd_hours_percentile,
    fs.session_length_percentile, fs.sessions_per_day_percentile,
    fs.fraud_risk_score, SYSUTCDATETIME()
  FROM #fraud_scores fs;
  
  -- ========================================================================
  -- STEP 6: INSERT INTO report_fraud TABLE
  -- ========================================================================
  
  DELETE FROM dbo.report_fraud WHERE client_id = @client_id;
  
  INSERT INTO dbo.report_fraud
  (
    client_id, emp_id, department, emp_role, site_name,
    risk_score, risk_type, score_explanation, computed_at
  )
  SELECT
    fs.client_id, fs.emp_id, fs.department, fs.emp_role,
    ISNULL(vs.site_name, N'') AS site_name,
    fs.fraud_risk_score AS risk_score,
    CASE
      WHEN fs.fraud_risk_score >= @risk_threshold_high THEN N'Critical Risk'
      WHEN fs.fraud_risk_score >= @risk_threshold_medium THEN N'High Risk'
      WHEN fs.fraud_risk_score >= @risk_threshold_low THEN N'Medium Risk'
      ELSE N'Low Risk'
    END AS risk_type,
    CONCAT(
      N'Door mismatch: ', CAST(CAST(fs.door_mismatch_percentile AS DECIMAL(5,1)) AS NVARCHAR(10)), N'%ile (', CAST(CAST(fs.door_mismatch_pct AS DECIMAL(5,1)) AS NVARCHAR(10)), N'%); ',
      N'Ping-pong: ', CAST(CAST(fs.pingpong_percentile AS DECIMAL(5,1)) AS NVARCHAR(10)), N'%ile (', CAST(CAST(fs.pingpong_pct AS DECIMAL(5,1)) AS NVARCHAR(10)), N'%); ',
      N'Odd hours: ', CAST(CAST(fs.odd_hours_percentile AS DECIMAL(5,1)) AS NVARCHAR(10)), N'%ile (', CAST(CAST(fs.odd_hours_pct AS DECIMAL(5,1)) AS NVARCHAR(10)), N'%); ',
      N'Session length: ', CAST(CAST(fs.session_length_percentile AS DECIMAL(5,1)) AS NVARCHAR(10)), N'%ile; ',
      N'Sessions/day: ', CAST(CAST(fs.sessions_per_day_percentile AS DECIMAL(5,1)) AS NVARCHAR(10)), N'%ile; ',
      N'Peer group: ', fs.peer_group_type, N' (n=', CAST(fs.peer_group_size AS NVARCHAR(10)), N')'
    ) AS score_explanation,
    SYSUTCDATETIME() AS computed_at
  FROM #fraud_scores fs
  LEFT JOIN dbo.v_client_emp_site vs ON vs.client_id = fs.client_id AND vs.emp_id = fs.emp_id;
  
  -- ========================================================================
  -- VALIDATION
  -- ========================================================================
  
  IF @@ROWCOUNT = 0
  BEGIN
    RAISERROR('usp_calc_fraud_risk_score: No rows inserted into report_fraud for client_id=%s. Check minimum data requirements.', 10, 1, @client_id);
  END
  
END
GO


