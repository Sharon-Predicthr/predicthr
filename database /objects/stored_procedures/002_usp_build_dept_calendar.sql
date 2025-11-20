

/****** Object:  StoredProcedure [dbo].[usp_build_dept_calendar]    Script Date: 16/11/2025 11:42:34 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_build_dept_calendar]
  @client_id NVARCHAR(50),
  @dept_threshold_pct INT = NULL
AS
BEGIN
  SET NOCOUNT ON;

  IF @dept_threshold_pct IS NULL
    SELECT TOP(1) @dept_threshold_pct = TRY_CAST(config_value AS INT)
    FROM dbo.risk_config
    WHERE (client_id=@client_id OR client_id IS NULL) AND config_key=N'dept_holiday_threshold_pct'
    ORDER BY CASE WHEN client_id=@client_id THEN 0 ELSE 1 END;
  IF @dept_threshold_pct IS NULL SET @dept_threshold_pct = 25;

  -- Map each emp to a single dept (latest by date/time)
  IF OBJECT_ID('tempdb..#emp_dept') IS NOT NULL DROP TABLE #emp_dept;
  SELECT a.emp_id,
         COALESCE(NULLIF(a.department,N''),N'Not Reported') AS department
  INTO #emp_dept
  FROM (
    SELECT emp_id,
           MAX(CONVERT(DATETIME2(0),CONCAT(CONVERT(VARCHAR(10),event_date,120),' ',CONVERT(VARCHAR(8),event_time,108)))) AS last_dt
    FROM dbo.attendance
    WHERE client_id=@client_id
    GROUP BY emp_id
  ) t
  JOIN dbo.attendance a
    ON a.client_id=@client_id
   AND a.emp_id=t.emp_id
   AND CONVERT(DATETIME2(0),CONCAT(CONVERT(VARCHAR(10),a.event_date,120),' ',CONVERT(VARCHAR(8),a.event_time,108)))=t.last_dt;

  -- Daily presence per dept
  IF OBJECT_ID('tempdb..#dept_present') IS NOT NULL DROP TABLE #dept_present;
  SELECT CAST(s.session_start AS DATE) AS d,
         ed.department,
         COUNT(DISTINCT s.emp_id) AS dept_present
  INTO #dept_present
  FROM dbo.emp_sessions s
  JOIN #emp_dept ed ON ed.emp_id=s.emp_id
  WHERE s.client_id=@client_id
  GROUP BY CAST(s.session_start AS DATE), ed.department;

  -- Dept active (distinct emp per dept over all time)
  IF OBJECT_ID('tempdb..#dept_active') IS NOT NULL DROP TABLE #dept_active;
  SELECT ed.department, COUNT(DISTINCT ed.emp_id) AS dept_active
  INTO #dept_active
  FROM #emp_dept ed
  GROUP BY ed.department;

  -- Date bounds from work_calendar (already exists)
  DECLARE @dmin DATE, @dmax DATE;
  SELECT @dmin=MIN(calendar_date), @dmax=MAX(calendar_date)
  FROM dbo.work_calendar WHERE client_id=@client_id;
  IF @dmin IS NULL OR @dmax IS NULL RETURN;

  -- Clear existing window and insert
  DELETE FROM dbo.work_calendar_dept
   WHERE client_id=@client_id AND calendar_date BETWEEN @dmin AND @dmax;

  INSERT INTO dbo.work_calendar_dept
    (client_id, calendar_date, department, dept_present, dept_active, dept_coverage_pct, is_workday_dept, computed_at)
  SELECT
    @client_id,
    dp.d,
    dp.department,
    dp.dept_present,
    COALESCE(da.dept_active,0) AS dept_active,
    CASE WHEN COALESCE(da.dept_active,0)=0 THEN 0 ELSE (dp.dept_present*100.0)/da.dept_active END AS dept_coverage_pct,
    CASE WHEN COALESCE(da.dept_active,0)=0 THEN 0
         WHEN (dp.dept_present*100.0)/da.dept_active >= @dept_threshold_pct THEN 1 ELSE 0 END AS is_workday_dept,
    SYSUTCDATETIME()
  FROM #dept_present dp
  LEFT JOIN #dept_active da ON da.department=dp.department;
END
GO

