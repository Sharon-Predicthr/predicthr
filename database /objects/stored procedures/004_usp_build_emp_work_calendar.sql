

/****** Object:  StoredProcedure [dbo].[usp_build_emp_work_calendar]    Script Date: 16/11/2025 11:46:59 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.usp_build_emp_work_calendar', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_build_emp_work_calendar;
GO


CREATE OR ALTER PROCEDURE [dbo].[usp_build_emp_work_calendar]
  @client_id NVARCHAR(50)
AS
BEGIN
  SET NOCOUNT ON;

  -----------------------------------------------------------------------
  -- 0) Quick guards: need org calendar OR sessions to define the window
  -----------------------------------------------------------------------
  IF NOT EXISTS (SELECT 1 FROM dbo.work_calendar WHERE client_id=@client_id)
     AND NOT EXISTS (SELECT 1 FROM dbo.emp_sessions WHERE client_id=@client_id)
  BEGIN
    RAISERROR('No work_calendar or emp_sessions for client_id=%s.',16,1,@client_id);
    RETURN;
  END

  -----------------------------------------------------------------------
  -- 1) Settings
  --    weekday inference threshold (%). Default 50 if not in risk_config
  -----------------------------------------------------------------------
  DECLARE @weekday_threshold_pct FLOAT;
  SELECT TOP(1) @weekday_threshold_pct =
         TRY_CONVERT(float, config_value)
  FROM dbo.risk_config
  WHERE (client_id=@client_id OR client_id IS NULL)
    AND config_key=N'calendar_work_threshold_pct'
  ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;

  IF @weekday_threshold_pct IS NULL SET @weekday_threshold_pct = 50.0;

  -----------------------------------------------------------------------
  -- 2) Date window: prefer org work_calendar window; fallback to sessions
  -----------------------------------------------------------------------
  DECLARE @min_d DATE, @max_d DATE;

  SELECT @min_d = MIN(calendar_date), @max_d = MAX(calendar_date)
  FROM dbo.work_calendar
  WHERE client_id=@client_id;

  IF @min_d IS NULL OR @max_d IS NULL
  BEGIN
    SELECT @min_d = MIN(CAST(session_start AS DATE)),
           @max_d = MAX(CAST(session_start AS DATE))
    FROM dbo.emp_sessions
    WHERE client_id=@client_id;
  END

  IF @min_d IS NULL OR @max_d IS NULL
  BEGIN
    RAISERROR('Unable to determine date range for client_id=%s.',16,1,@client_id);
    RETURN;
  END

  -----------------------------------------------------------------------
  -- 3) Build per-employee list (anyone who appears in sessions)
  -----------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#emps') IS NOT NULL DROP TABLE #emps;
  SELECT DISTINCT emp_id
  INTO #emps
  FROM dbo.emp_sessions
  WHERE client_id=@client_id;

  IF NOT EXISTS (SELECT 1 FROM #emps)
  BEGIN
    RAISERROR('No employees in emp_sessions for client_id=%s.',16,1,@client_id);
    RETURN;
  END

  -----------------------------------------------------------------------
  -- 4) Build a dates table inside the chosen window
  -----------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#dates') IS NOT NULL DROP TABLE #dates;
  ;WITH X(N) AS (
      SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
      UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
  ),
  Tally(N) AS (
      SELECT TOP (DATEDIFF(DAY,@min_d,@max_d)+1)
             ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1
      FROM X a, X b, X c, X d, X e
  )
  SELECT DATEADD(DAY, N, @min_d) AS d
  INTO #dates
  FROM Tally;

  -----------------------------------------------------------------------
  -- 5) Start fresh for this client_id
  -----------------------------------------------------------------------
  DELETE FROM dbo.emp_work_calendar WHERE client_id=@client_id;

  -----------------------------------------------------------------------
  -- 6) Insert skeleton rows: one row per emp per date
  -----------------------------------------------------------------------
  INSERT INTO dbo.emp_work_calendar
    (client_id, emp_id, calendar_date, is_working, source_reason)
  SELECT
    @client_id, e.emp_id, d.d,
    0 AS is_working,
    N'init' AS source_reason
  FROM #emps e
  CROSS JOIN #dates d;

  -----------------------------------------------------------------------
  -- 7) Company-off overlay from work_calendar (if provided)
  -----------------------------------------------------------------------
  UPDATE ewc
    SET ewc.is_working = CASE WHEN wc.is_workday=1 THEN ewc.is_working ELSE 0 END,
        ewc.source_reason = CASE WHEN wc.is_workday=1 THEN ewc.source_reason ELSE N'company_off' END
  FROM dbo.emp_work_calendar ewc
  JOIN dbo.work_calendar wc
    ON wc.client_id = ewc.client_id
   AND wc.calendar_date = ewc.calendar_date
  WHERE ewc.client_id=@client_id;

  -----------------------------------------------------------------------
  -- 8) Mark presence days as working (authoritative)
  -----------------------------------------------------------------------
  -- distinct (emp_id, date) from sessions
  IF OBJECT_ID('tempdb..#pres') IS NOT NULL DROP TABLE #pres;
  SELECT DISTINCT emp_id, CAST(session_start AS DATE) AS d
  INTO #pres
  FROM dbo.emp_sessions
  WHERE client_id=@client_id;

  UPDATE ewc
     SET ewc.is_working = 1,
         ewc.source_reason = N'presence'
  FROM dbo.emp_work_calendar ewc
  JOIN #pres p
    ON p.emp_id=ewc.emp_id AND p.d=ewc.calendar_date
  WHERE ewc.client_id=@client_id;

  -----------------------------------------------------------------------
  -- 9) Weekday coverage per employee (use only dates NOT already presence)
  -----------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#dow_cov') IS NOT NULL DROP TABLE #dow_cov;
  SELECT
    ewc.emp_id,
    DATEPART(WEEKDAY, ewc.calendar_date) AS dow,
    COUNT(*) AS total_days,
    SUM(CASE WHEN ewc.is_working=1 AND ewc.source_reason=N'presence' THEN 1 ELSE 0 END) AS pres_days
  INTO #dow_cov
  FROM dbo.emp_work_calendar ewc
  WHERE ewc.client_id=@client_id
  GROUP BY ewc.emp_id, DATEPART(WEEKDAY, ewc.calendar_date);

  -- Determine which weekdays are "normally working" per employee
  IF OBJECT_ID('tempdb..#dow_flag') IS NOT NULL DROP TABLE #dow_flag;
  SELECT
    emp_id,
    dow,
    CASE
      WHEN total_days = 0 THEN 0
      WHEN (pres_days * 100.0) / total_days >= @weekday_threshold_pct THEN 1
      ELSE 0
    END AS is_working_weekday
  INTO #dow_flag
  FROM #dow_cov;

  -----------------------------------------------------------------------
  -- 10) For non-presence rows, lift to working if weekday is flagged
  -----------------------------------------------------------------------
  UPDATE ewc
    SET ewc.is_working = 1,
        ewc.source_reason = CASE WHEN ewc.source_reason = N'company_off'
                                 THEN N'company_off'       -- keep company_off if org calendar said off
                                 ELSE N'baseline_weekday_pattern'
                            END
  FROM dbo.emp_work_calendar ewc
  JOIN #dow_flag f
    ON f.emp_id=ewc.emp_id
   AND f.dow = DATEPART(WEEKDAY, ewc.calendar_date)
  WHERE ewc.client_id=@client_id
    AND ewc.is_working = 0         -- only for rows not already presence
    AND f.is_working_weekday = 1;

  -- Done
END
GO

