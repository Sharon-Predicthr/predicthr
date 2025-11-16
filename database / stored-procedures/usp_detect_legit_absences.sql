

/****** Object:  StoredProcedure [dbo].[usp_detect_legit_absences]    Script Date: 16/11/2025 11:50:43 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_detect_legit_absences]
  @client_id NVARCHAR(50),
  @pto_min_block_days        INT   = NULL,
  @sick_max_block_days       INT   = NULL,
  @org_holiday_threshold_pct INT   = NULL,
  @conf_full_excl            FLOAT = NULL,
  @conf_partial_min          FLOAT = NULL
AS
BEGIN
  SET NOCOUNT ON;

  -- Config
  IF @pto_min_block_days IS NULL
    SELECT TOP(1) @pto_min_block_days = TRY_CAST(config_value AS INT)
    FROM dbo.risk_config WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'pto_min_block_days'
    ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;
  IF @pto_min_block_days IS NULL SET @pto_min_block_days=5;

  IF @sick_max_block_days IS NULL
    SELECT TOP(1) @sick_max_block_days = TRY_CAST(config_value AS INT)
    FROM dbo.risk_config WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'sick_max_block_days'
    ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;
  IF @sick_max_block_days IS NULL SET @sick_max_block_days=3;

  IF @org_holiday_threshold_pct IS NULL
    SELECT TOP(1) @org_holiday_threshold_pct = TRY_CAST(config_value AS INT)
    FROM dbo.risk_config WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'holiday_coverage_threshold_pct'
    ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;
  IF @org_holiday_threshold_pct IS NULL SET @org_holiday_threshold_pct=15;

  IF @conf_full_excl IS NULL
    SELECT TOP(1) @conf_full_excl = TRY_CAST(config_value AS FLOAT)
    FROM dbo.risk_config WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'legit_conf_full_exclude_min'
    ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;
  IF @conf_full_excl IS NULL SET @conf_full_excl=0.6;

  IF @conf_partial_min IS NULL
    SELECT TOP(1) @conf_partial_min = TRY_CAST(config_value AS FLOAT)
    FROM dbo.risk_config WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'legit_conf_partial_min'
    ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;
  IF @conf_partial_min IS NULL SET @conf_partial_min=0.3;

  -- Optional scope limit
  DECLARE @limit_days INT = TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config
                                      WHERE (client_id=@client_id OR client_id IS NULL)
                                        AND config_key=N'legit_window_days'
                                      ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END) AS INT);
  IF @limit_days IS NULL SET @limit_days = 365;

  -- Clear
  DELETE FROM dbo.emp_day_legit    WHERE client_id=@client_id;
  DELETE FROM dbo.legit_abs_blocks WHERE client_id=@client_id;

  -- Analysis window from work_calendar (bounded by @limit_days)
  DECLARE @dmax DATE = (SELECT MAX(calendar_date) FROM dbo.work_calendar WHERE client_id=@client_id);
  IF @dmax IS NULL RETURN;
  DECLARE @dmin DATE = DATEADD(DAY, -@limit_days, @dmax);

  -- Workday grid (org)
  IF OBJECT_ID('tempdb..#wd') IS NOT NULL DROP TABLE #wd;
  SELECT calendar_date AS d,
         is_workday,
         CASE WHEN coverage_pct < @org_holiday_threshold_pct THEN 1 ELSE 0 END AS is_org_off
  INTO #wd
  FROM dbo.work_calendar
  WHERE client_id=@client_id
    AND calendar_date BETWEEN @dmin AND @dmax;

  -- Presence days (distinct)
  IF OBJECT_ID('tempdb..#present') IS NOT NULL DROP TABLE #present;
  SELECT DISTINCT s.emp_id, CAST(s.session_start AS DATE) AS d
  INTO #present
  FROM dbo.emp_sessions s
  WHERE s.client_id=@client_id
    AND CAST(s.session_start AS DATE) BETWEEN @dmin AND @dmax;

  -- All employees in scope
  IF OBJECT_ID('tempdb..#emps') IS NOT NULL DROP TABLE #emps;
  SELECT DISTINCT emp_id INTO #emps
  FROM dbo.attendance WHERE client_id=@client_id;

  -- Absent workdays (set-based)
  IF OBJECT_ID('tempdb..#abs') IS NOT NULL DROP TABLE #abs;
  SELECT e.emp_id, w.d,
         ROW_NUMBER() OVER (PARTITION BY e.emp_id ORDER BY w.d) AS rn,
         DATEDIFF(DAY, CONVERT(DATE,'19000101'), w.d) AS dkey
  INTO #abs
  FROM #emps e
  JOIN #wd w ON w.is_workday=1 AND w.is_org_off=0
  LEFT JOIN #present p ON p.emp_id=e.emp_id AND p.d=w.d
  WHERE p.emp_id IS NULL;   -- absent on a workday, org not off

  -- Group consecutive absences by emp: grp = dkey - rn
  IF OBJECT_ID('tempdb..#abs_grp') IS NOT NULL DROP TABLE #abs_grp;
  SELECT emp_id,
         MIN(d) AS block_start,
         MAX(d) AS block_end,
         COUNT(*) AS block_days
  INTO #abs_grp
  FROM (
    SELECT emp_id, d, (dkey - rn) AS grp_key
    FROM #abs
  ) x
  GROUP BY emp_id, grp_key;

  -- Classify & write blocks
  INSERT INTO dbo.legit_abs_blocks(client_id, emp_id, block_start, block_end, block_days, inferred_reason, confidence, dept_support_pct, is_full_exclude)
  SELECT
    @client_id,
    g.emp_id,
    g.block_start,
    g.block_end,
    g.block_days,
    CASE WHEN g.block_days >= @pto_min_block_days THEN N'vacation_like' ELSE N'sick_like' END AS inferred_reason,
    CASE WHEN g.block_days >= @pto_min_block_days
         THEN 0.6  -- base for PTO-like
         ELSE CASE g.block_days WHEN 1 THEN 0.4 WHEN 2 THEN 0.55 ELSE 0.6 END END AS confidence,
    NULL,
    CASE WHEN (CASE WHEN g.block_days >= @pto_min_block_days THEN 0.6 ELSE CASE g.block_days WHEN 1 THEN 0.4 WHEN 2 THEN 0.55 ELSE 0.6 END END) >= @conf_full_excl
         THEN 1 ELSE 0 END AS is_full_exclude
  FROM #abs_grp g;

  -- Per-day legit flags from blocks
  INSERT INTO dbo.emp_day_legit(client_id, emp_id, calendar_date, is_legit_absent, inferred_reason, confidence, source_note)
  SELECT
    @client_id, b.emp_id, dd.d, 1, b.inferred_reason, b.confidence, N'block_detected'
  FROM dbo.legit_abs_blocks b
  JOIN #wd dd ON dd.d BETWEEN b.block_start AND b.block_end
  WHERE b.client_id=@client_id;

  -- Plus org_off legit for absentees (single pass)
  INSERT INTO dbo.emp_day_legit(client_id, emp_id, calendar_date, is_legit_absent, inferred_reason, confidence, source_note)
  SELECT @client_id, e.emp_id, w.d, 1, N'org_off', 0.8, N'org_coverage_below_threshold'
  FROM #emps e
  JOIN #wd w ON w.is_org_off=1
  LEFT JOIN #present p ON p.emp_id=e.emp_id AND p.d=w.d
  WHERE p.emp_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM dbo.emp_day_legit L
                    WHERE L.client_id=@client_id AND L.emp_id=e.emp_id AND L.calendar_date=w.d);
END
GO

