
/****** Object:  StoredProcedure [dbo].[usp_infer_work_calendar]    Script Date: 16/11/2025 11:52:09 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


IF OBJECT_ID('dbo.usp_infer_work_calendar', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_infer_work_calendar;
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_infer_work_calendar]
  @client_id             NVARCHAR(50),
  @workday_threshold_pct INT = NULL   -- if NULL → read from risk_config (client→global→default 50)
AS
BEGIN
  SET NOCOUNT ON;

-- Derive observed window from attendance
  DECLARE @att_start DATE, @att_end DATE;
  SELECT @att_start = MIN(a.event_date), @att_end = MAX(a.event_date)
  FROM dbo.attendance a
  WHERE a.client_id = @client_id;

  IF @att_start IS NULL OR @att_end IS NULL
    RETURN; -- nothing to do

-- Ensure calendar only covers observed range
DELETE FROM dbo.work_calendar
WHERE client_id=@client_id
  AND (calendar_date < @att_start OR calendar_date > @att_end);

-- (If you generate/insert rows here, generate only for @att_start..@att_end)


  IF @workday_threshold_pct IS NULL
  BEGIN
    SELECT TOP(1) @workday_threshold_pct = TRY_CAST(config_value AS INT)
    FROM dbo.risk_config
    WHERE config_key = N'calendar_work_threshold_pct' AND client_id = @client_id;

    IF @workday_threshold_pct IS NULL
      SELECT TOP(1) @workday_threshold_pct = TRY_CAST(config_value AS INT)
      FROM dbo.risk_config
      WHERE config_key = N'calendar_work_threshold_pct' AND client_id IS NULL;

    IF @workday_threshold_pct IS NULL SET @workday_threshold_pct = 50;
  END

  DECLARE @from_date DATE, @thru_date DATE;

  SELECT @from_date = MIN(CAST(session_start AS DATE)),
         @thru_date = MAX(CAST(session_start AS DATE))
  FROM dbo.emp_sessions
  WHERE client_id = @client_id;

  IF @from_date IS NULL OR @thru_date IS NULL
  BEGIN
    SELECT @from_date = MIN(event_date), @thru_date = MAX(event_date)
    FROM dbo.attendance WHERE client_id = @client_id;
  END

  IF @from_date IS NULL OR @thru_date IS NULL OR @from_date > @thru_date
  BEGIN
    DELETE FROM dbo.work_calendar WHERE client_id = @client_id;
    RETURN;
  END

  IF OBJECT_ID('tempdb..#days') IS NOT NULL DROP TABLE #days;
  CREATE TABLE #days(d DATE NOT NULL PRIMARY KEY);
  DECLARE @d DATE = @from_date;
  WHILE @d <= @thru_date BEGIN INSERT INTO #days VALUES(@d); SET @d = DATEADD(DAY,1,@d); END

  DECLARE @active_emp INT = 0;
  SELECT @active_emp = COUNT(DISTINCT emp_id)
  FROM dbo.emp_sessions
  WHERE client_id = @client_id AND CAST(session_start AS DATE) BETWEEN @from_date AND @thru_date;

  IF ISNULL(@active_emp,0) = 0
    SELECT @active_emp = COUNT(DISTINCT emp_id)
    FROM dbo.attendance
    WHERE client_id = @client_id AND event_date BETWEEN @from_date AND @thru_date;

  IF ISNULL(@active_emp,0) = 0
  BEGIN
    DELETE FROM dbo.work_calendar WHERE client_id = @client_id AND calendar_date BETWEEN @from_date AND @thru_date;
    RETURN;
  END

  IF OBJECT_ID('tempdb..#present') IS NOT NULL DROP TABLE #present;
  CREATE TABLE #present(calendar_date DATE PRIMARY KEY, present_emp INT NOT NULL);

  INSERT INTO #present(calendar_date, present_emp)
  SELECT d.d, COUNT(DISTINCT s.emp_id)
  FROM #days d
  LEFT JOIN dbo.emp_sessions s
    ON s.client_id = @client_id AND CAST(s.session_start AS DATE) = d.d
  GROUP BY d.d;

  DELETE FROM dbo.work_calendar
  WHERE client_id = @client_id AND calendar_date BETWEEN @from_date AND @thru_date;

  DECLARE @now DATETIME2(0) = SYSUTCDATETIME();

  INSERT INTO dbo.work_calendar
    (client_id, calendar_date, is_workday, present_emp, active_emp, coverage_pct, detection_method, computed_at, day_of_week)
  SELECT
    @client_id,
    p.calendar_date,
    CASE WHEN @active_emp=0 THEN 0
         WHEN (p.present_emp*100.0)/@active_emp >= @workday_threshold_pct THEN 1 ELSE 0 END AS is_workday,
    p.present_emp,
    @active_emp,
    CASE WHEN @active_emp=0 THEN 0.0 ELSE (p.present_emp*100.0)/@active_emp END AS coverage_pct,
    N'auto',
    @now,
    DATENAME(weekday, p.calendar_date)
  FROM #present p;
END
GO

