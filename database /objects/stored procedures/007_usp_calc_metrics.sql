
/****** Object:  StoredProcedure [dbo].[usp_calc_metrics]    Script Date: 16/11/2025 11:48:23 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_calc_metrics]
  @client_id NVARCHAR(50)
AS
BEGIN
  SET NOCOUNT ON;

  /* --------------------------- Guard --------------------------- */
  IF @client_id IS NULL OR LTRIM(RTRIM(@client_id)) = N''
  BEGIN
    RAISERROR('usp_calc_metrics: @client_id is required.', 16, 1);
    RETURN;
  END

  /* ----------------------- Tunable thresholds ------------------ */
  DECLARE
      @long_minutes INT  = 540          -- 9 hours for "long day"
    , @late_after   TIME = '09:30:00'   -- first-in after this is "late start"
    , @pingpong_min_sessions INT = 3    -- 3+ sessions in a day -> ping-pong
    , @short_gap_max INT = 2;           -- off-streaks up to this length count as "short gaps"

  /* ------------------ Resolve analysis windows ----------------- */
  DECLARE
      @baseline_start DATE
    , @baseline_end   DATE
    , @recent_start   DATE
    , @recent_end     DATE;

  SELECT TOP(1) @baseline_start = TRY_CONVERT(date, config_value)
  FROM dbo.risk_config
  WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'baseline_start'
  ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;

  SELECT TOP(1) @baseline_end = TRY_CONVERT(date, config_value)
  FROM dbo.risk_config
  WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'baseline_end'
  ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;

  SELECT TOP(1) @recent_start = TRY_CONVERT(date, config_value)
  FROM dbo.risk_config
  WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'recent_start'
  ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;

  SELECT TOP(1) @recent_end = TRY_CONVERT(date, config_value)
  FROM dbo.risk_config
  WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'recent_end'
  ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;

  IF @recent_end IS NULL
    SELECT @recent_end = MAX(calendar_date)
    FROM dbo.emp_work_calendar
    WHERE client_id=@client_id;

  IF @recent_start IS NULL SET @recent_start = DATEADD(DAY, -60, @recent_end);
  IF @baseline_end IS NULL  SET @baseline_end = DATEADD(DAY, -1, @recent_start);

  IF @baseline_start IS NULL
    SELECT @baseline_start = MIN(calendar_date)
    FROM dbo.emp_work_calendar
    WHERE client_id=@client_id;

  IF @baseline_start IS NULL OR @baseline_end IS NULL OR @recent_start IS NULL OR @recent_end IS NULL
  BEGIN
    RAISERROR('sp_calc_metrics: Unable to infer analysis windows for client_id=%s.', 16, 1, @client_id);
    RETURN;
  END

  /* -------------------- Employee universe ---------------------- */
  IF OBJECT_ID('tempdb..#emp') IS NOT NULL DROP TABLE #emp;
  SELECT DISTINCT emp_id
  INTO #emp
  FROM dbo.emp_sessions
  WHERE client_id=@client_id;

  INSERT INTO #emp(emp_id)
  SELECT DISTINCT e.emp_id
  FROM dbo.emp_work_calendar e
  WHERE e.client_id=@client_id
    AND NOT EXISTS (SELECT 1 FROM #emp t WHERE t.emp_id=e.emp_id);

  /* ------------- Latest dept/role from attendance -------------- */
  IF OBJECT_ID('tempdb..#emp_meta') IS NOT NULL DROP TABLE #emp_meta;

  SELECT x.emp_id,
         COALESCE(NULLIF(LTRIM(RTRIM(x.department)),N''), N'Not Reported') AS department,
         COALESCE(NULLIF(LTRIM(RTRIM(x.emp_role)),N''),   N'Not Reported') AS emp_role
  INTO #emp_meta
  FROM (
    SELECT a.emp_id, a.department, a.emp_role,
           ROW_NUMBER() OVER (PARTITION BY a.emp_id ORDER BY a.event_date DESC, a.event_time DESC, a.emp_id) AS rn
    FROM dbo.attendance a
    WHERE a.client_id=@client_id
  ) x
  WHERE x.rn=1;

  -- Backfill any missing employees
  INSERT INTO #emp_meta(emp_id, department, emp_role)
  SELECT e.emp_id, N'Not Reported', N'Not Reported'
  FROM #emp e
  WHERE NOT EXISTS (SELECT 1 FROM #emp_meta m WHERE m.emp_id=e.emp_id);

  /* ----------------- Denominators (workdays) ------------------- */
  IF OBJECT_ID('tempdb..#denoms') IS NOT NULL DROP TABLE #denoms;
  SELECT
      w.emp_id,
      SUM(CASE WHEN w.calendar_date BETWEEN @baseline_start AND @baseline_end AND w.is_working=1 THEN 1 ELSE 0 END) AS denom_b_emp,
      SUM(CASE WHEN w.calendar_date BETWEEN @recent_start   AND @recent_end   AND w.is_working=1 THEN 1 ELSE 0 END) AS denom_r_emp
  INTO #denoms
  FROM dbo.emp_work_calendar w
  WHERE w.client_id=@client_id
  GROUP BY w.emp_id;

  /* ----------- Daily sessions & flags (baseline/recent) -------- */
  IF OBJECT_ID('tempdb..#sess_days') IS NOT NULL DROP TABLE #sess_days;
  SELECT s.emp_id,
         CAST(s.session_start AS DATE) AS work_date,
         MIN(CAST(s.session_start AS TIME)) AS first_in_time,
         SUM(s.minutes_worked) AS minutes_sum,
         COUNT(*) AS sessions_cnt,
         MAX(CASE WHEN s.any_remote=1 THEN 1 ELSE 0 END) AS any_remote_day,
         MAX(CASE WHEN s.in_door IS NOT NULL AND s.out_door IS NOT NULL AND s.in_door<>s.out_door THEN 1 ELSE 0 END) AS door_mismatch_day
  INTO #sess_days
  FROM dbo.emp_sessions s
  WHERE s.client_id=@client_id
    AND CAST(s.session_start AS DATE) BETWEEN @baseline_start AND @recent_end
  GROUP BY s.emp_id, CAST(s.session_start AS DATE);

  /* Baseline aggregates (presence days = count of rows in that window) */
  IF OBJECT_ID('tempdb..#base_agg') IS NOT NULL DROP TABLE #base_agg;
  SELECT d.emp_id,
         COUNT(*) AS pres_b,
         AVG(CAST(d.minutes_sum AS FLOAT)) AS avg_min_b
  INTO #base_agg
  FROM #sess_days d
  WHERE d.work_date BETWEEN @baseline_start AND @baseline_end
  GROUP BY d.emp_id;

  /* Recent aggregates and rates */
  IF OBJECT_ID('tempdb..#recent_agg') IS NOT NULL DROP TABLE #recent_agg;
  SELECT d.emp_id,
         COUNT(*) AS pres_r,
         AVG(CAST(d.minutes_sum AS FLOAT)) AS avg_min_r,
         SUM(CASE WHEN d.minutes_sum >= @long_minutes THEN 1 ELSE 0 END) AS long_days,
         SUM(CASE WHEN d.first_in_time > @late_after THEN 1 ELSE 0 END) AS late_days,
         SUM(CASE WHEN d.door_mismatch_day=1 THEN 1 ELSE 0 END) AS door_mis_days,
         SUM(CASE WHEN d.sessions_cnt >= @pingpong_min_sessions THEN 1 ELSE 0 END) AS pingpong_days,
         SUM(CASE WHEN d.any_remote_day=1 THEN 1 ELSE 0 END) AS odd_days
  INTO #recent_agg
  FROM #sess_days d
  WHERE d.work_date BETWEEN @recent_start AND @recent_end
  GROUP BY d.emp_id;

  /* -------------------- Presence & normals --------------------- */
  IF OBJECT_ID('tempdb..#calc') IS NOT NULL DROP TABLE #calc;
  SELECT
      e.emp_id,
      @baseline_start AS baseline_start,
      @baseline_end   AS baseline_end,
      ISNULL(dn.denom_b_emp,0) AS baseline_days,
      @recent_start   AS recent_start,
      @recent_end     AS recent_end,
      ISNULL(dn.denom_r_emp,0) AS recent_days,
      ISNULL(b.pres_b,0) AS pres_b,
      ISNULL(r.pres_r,0) AS pres_r,
      CASE WHEN ISNULL(dn.denom_b_emp,0)=0 THEN 0.0 ELSE (ISNULL(b.pres_b,0)*100.0)/NULLIF(dn.denom_b_emp,0) END AS pres_b_norm,
      CASE WHEN ISNULL(dn.denom_r_emp,0)=0 THEN 0.0 ELSE (ISNULL(r.pres_r,0)*100.0)/NULLIF(dn.denom_r_emp,0) END AS pres_r_norm
  INTO #calc
  FROM #emp e
  LEFT JOIN #denoms     dn ON dn.emp_id=e.emp_id
  LEFT JOIN #base_agg    b ON b.emp_id=e.emp_id
  LEFT JOIN #recent_agg  r ON r.emp_id=e.emp_id;

  /* ----------------- Workload & Integrity rates ---------------- */
  IF OBJECT_ID('tempdb..#work_integ') IS NOT NULL DROP TABLE #work_integ;
  SELECT
      e.emp_id,
      /* workload */
      CASE WHEN ISNULL(r.pres_r,0)=0 THEN 0.0 ELSE r.long_days*100.0/NULLIF(r.pres_r,0) END AS long_r,
      CASE WHEN ISNULL(r.pres_r,0)=0 THEN 0.0 ELSE r.late_days*100.0/NULLIF(r.pres_r,0) END AS late_r,
      b.avg_min_b,
      r.avg_min_r,
      /* integrity */
      CASE WHEN ISNULL(r.pres_r,0)=0 THEN 0.0 ELSE r.odd_days*100.0/NULLIF(r.pres_r,0) END AS odd_pct_r,
      CASE WHEN ISNULL(r.pres_r,0)=0 THEN 0.0 ELSE r.door_mis_days*100.0/NULLIF(r.pres_r,0) END AS door_mis_pct_r,
      CASE WHEN ISNULL(r.pres_r,0)=0 THEN 0.0 ELSE r.pingpong_days*100.0/NULLIF(r.pres_r,0) END AS pingpong_pct_r
  INTO #work_integ
  FROM #emp e
  LEFT JOIN #recent_agg r ON r.emp_id=e.emp_id
  LEFT JOIN #base_agg  b ON b.emp_id=e.emp_id;

  /* ------------------- Off streaks (recent) -------------------- */
  /* Working days with no presence => off=1 */
  IF OBJECT_ID('tempdb..#recent_days') IS NOT NULL DROP TABLE #recent_days;
  SELECT w.emp_id,
         w.calendar_date,
         CASE WHEN sd.emp_id IS NULL THEN 1 ELSE 0 END AS off_day
  INTO #recent_days
  FROM dbo.emp_work_calendar w
  LEFT JOIN (
    SELECT DISTINCT emp_id, work_date
    FROM #sess_days
    WHERE work_date BETWEEN @recent_start AND @recent_end
  ) sd
    ON sd.emp_id=w.emp_id AND sd.work_date=w.calendar_date
  WHERE w.client_id=@client_id
    AND w.calendar_date BETWEEN @recent_start AND @recent_end
    AND w.is_working=1;

  /* Label consecutive off segments using islands technique */
  IF OBJECT_ID('tempdb..#off_runs') IS NOT NULL DROP TABLE #off_runs;
  SELECT emp_id,
         MIN(calendar_date) AS run_start,
         MAX(calendar_date) AS run_end,
         COUNT(*) AS run_len
  INTO #off_runs
  FROM (
    SELECT rd.*,
           /* group id: advances only when off_day resets */
           DATEADD(DAY,
                   -ROW_NUMBER() OVER (PARTITION BY emp_id ORDER BY calendar_date),
                   calendar_date) AS grp
    FROM #recent_days rd
    WHERE rd.off_day=1
  ) z
  GROUP BY emp_id, grp;

  IF OBJECT_ID('tempdb..#off_stats') IS NOT NULL DROP TABLE #off_stats;
  SELECT e.emp_id,
         ISNULL((
           SELECT MAX(run_len) FROM #off_runs r WHERE r.emp_id=e.emp_id
         ),0) AS max_off_run,
         ISNULL((
           SELECT COUNT(*) FROM #off_runs r WHERE r.emp_id=e.emp_id AND r.run_len BETWEEN 1 AND @short_gap_max
         ),0) AS short_gap_count_r
  INTO #off_stats
  FROM #emp e;

  /* -------------------- Write calculated_data ------------------ */
  DELETE FROM dbo.calculated_data WHERE client_id=@client_id;

  INSERT INTO dbo.calculated_data
  (
    client_id, emp_id, department, emp_role, site_name,
    baseline_start, baseline_end, baseline_days,
    recent_start, recent_end, recent_days,
    pres_b, pres_b_norm, pres_r, pres_r_norm,
    max_off_run, short_gap_count_r, long_r, late_r,
    avg_min_b, avg_min_r, odd_pct_r, door_mis_pct_r, pingpong_pct_r,
    pres_b_norm_adj, pres_r_norm_adj,
    max_off_run_adj, short_gap_count_r_adj,
    legit_abs_days_b, legit_abs_days_r, legit_abs_conf_avg_r
  )
  SELECT
    @client_id,
    c.emp_id,
    m.department,
    m.emp_role,
	vs.site_name,
    c.baseline_start, c.baseline_end, c.baseline_days,
    c.recent_start,   c.recent_end,   c.recent_days,
    c.pres_b, c.pres_b_norm, c.pres_r, c.pres_r_norm,
    os.max_off_run,
    os.short_gap_count_r,
    wi.long_r,
    wi.late_r,
    wi.avg_min_b,
    wi.avg_min_r,
    wi.odd_pct_r,
    wi.door_mis_pct_r,
    wi.pingpong_pct_r,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM #calc c
  LEFT JOIN #emp_meta   m  ON m.emp_id=c.emp_id
  LEFT JOIN #work_integ wi ON wi.emp_id=c.emp_id
  LEFT JOIN #off_stats  os ON os.emp_id=c.emp_id
  LEFT JOIN v_client_emp_site vs ON vs.client_id = @client_id AND vs.emp_id = c.emp_id

  IF @@ROWCOUNT = 0
  BEGIN
    RAISERROR('sp_calc_metrics: No rows written into calculated_data for client_id=%s.', 16, 1, @client_id);
    RETURN;
  END
END
GO

