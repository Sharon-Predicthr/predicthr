
/****** Object:  StoredProcedure [dbo].[usp_calc_sessions]    Script Date: 16/11/2025 11:49:39 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


IF OBJECT_ID('dbo.usp_calc_sessions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_calc_sessions;
GO


CREATE OR ALTER PROCEDURE [dbo].[usp_calc_sessions]
  @client_id         NVARCHAR(50),
  @in_fallback_time  TIME(0) = '09:00',
  @out_fallback_time TIME(0) = '17:00'
AS
BEGIN
  SET NOCOUNT ON;

  /* Guardrails */
  IF @client_id IS NULL OR LTRIM(RTRIM(@client_id)) = N''
  BEGIN
    RAISERROR('sp_calc_sessions: @client_id is required',16,1);
    RETURN;
  END

  /* Stage base punches (per emp, per date) */
  IF OBJECT_ID('tempdb..#base') IS NOT NULL DROP TABLE #base;
  CREATE TABLE #base
  (
    emp_id     NVARCHAR(100) NOT NULL,
    work_date  DATE          NOT NULL,
    event_time TIME(0)       NOT NULL,
    door_id    NVARCHAR(200) NULL
  );

  INSERT INTO #base(emp_id, work_date, event_time, door_id)
  SELECT a.emp_id,
         a.event_date AS work_date,
         a.event_time,
         a.door_id
  FROM dbo.attendance a
  WHERE a.client_id = @client_id;

  /* First and last time per emp/date (with time fallbacks) */
  IF OBJECT_ID('tempdb..#day_span') IS NOT NULL DROP TABLE #day_span;
  CREATE TABLE #day_span
  (
    emp_id    NVARCHAR(100) NOT NULL,
    work_date DATE          NOT NULL,
    in_time   TIME(0)       NOT NULL,
    out_time  TIME(0)       NOT NULL,
    PRIMARY KEY(emp_id, work_date)
  );

  INSERT INTO #day_span(emp_id, work_date, in_time, out_time)
  SELECT
    b.emp_id,
    b.work_date,
    COALESCE(MIN(b.event_time), @in_fallback_time)  AS in_time,
    COALESCE(MAX(b.event_time), @out_fallback_time) AS out_time
  FROM #base AS b
  GROUP BY b.emp_id, b.work_date;

  /* Pick doors at first/last punch (if those exact times exist) */
  IF OBJECT_ID('tempdb..#doors') IS NOT NULL DROP TABLE #doors;
  CREATE TABLE #doors
  (
    emp_id    NVARCHAR(100) NOT NULL,
    work_date DATE          NOT NULL,
    in_door   NVARCHAR(200) NULL,
    out_door  NVARCHAR(200) NULL,
    PRIMARY KEY(emp_id, work_date)
  );

  ;WITH first_last AS (
    SELECT d.emp_id, d.work_date, d.in_time, d.out_time
    FROM #day_span d
  )
  INSERT INTO #doors(emp_id, work_date, in_door, out_door)
  SELECT
    f.emp_id,
    f.work_date,
    (SELECT TOP(1) b.door_id FROM #base b
      WHERE b.emp_id=f.emp_id AND b.work_date=f.work_date AND b.event_time=f.in_time
      ORDER BY b.event_time ASC),
    (SELECT TOP(1) b.door_id FROM #base b
      WHERE b.emp_id=f.emp_id AND b.work_date=f.work_date AND b.event_time=f.out_time
      ORDER BY b.event_time DESC)
  FROM first_last f;

  /* Build final sessions */
  IF OBJECT_ID('tempdb..#final') IS NOT NULL DROP TABLE #final;
  CREATE TABLE #final
  (
    client_id      NVARCHAR(50)  NOT NULL,
    emp_id         NVARCHAR(100) NOT NULL,
    session_start  DATETIME2(0)  NOT NULL,
    session_end    DATETIME2(0)  NOT NULL,
    minutes_worked INT           NOT NULL,
    in_door        NVARCHAR(200) NULL,
    out_door       NVARCHAR(200) NULL,
    any_remote     BIT           NOT NULL
  );

  INSERT INTO #final(client_id, emp_id, session_start, session_end, minutes_worked, in_door, out_door, any_remote)
  SELECT
    @client_id AS client_id,
    s.emp_id,
    DATETIMEFROMPARTS(YEAR(s.work_date), MONTH(s.work_date), DAY(s.work_date),
                      DATEPART(HOUR, s.in_time), DATEPART(MINUTE, s.in_time), 0, 0)  AS session_start,
    DATETIMEFROMPARTS(YEAR(s.work_date), MONTH(s.work_date), DAY(s.work_date),
                      DATEPART(HOUR, s.out_time), DATEPART(MINUTE, s.out_time), 0, 0) AS session_end,
    CASE
      WHEN s.out_time >= s.in_time
        THEN DATEDIFF(MINUTE,
                      DATETIMEFROMPARTS(YEAR(s.work_date), MONTH(s.work_date), DAY(s.work_date),
                                        DATEPART(HOUR, s.in_time), DATEPART(MINUTE, s.in_time), 0, 0),
                      DATETIMEFROMPARTS(YEAR(s.work_date), MONTH(s.work_date), DAY(s.work_date),
                                        DATEPART(HOUR, s.out_time), DATEPART(MINUTE, s.out_time), 0, 0))
      ELSE 0
    END AS minutes_worked,
    d.in_door,
    d.out_door,
    CASE
      WHEN (d.in_door  IS NOT NULL AND d.in_door  LIKE N'%REMOTE%')
        OR (d.out_door IS NOT NULL AND d.out_door LIKE N'%REMOTE%')
      THEN 1 ELSE 0
    END AS any_remote
  FROM #day_span s
  LEFT JOIN #doors d ON d.emp_id = s.emp_id AND d.work_date = s.work_date;

  /* Replace this client’s snapshot */
  DELETE FROM dbo.emp_sessions WHERE client_id = @client_id;

  INSERT INTO dbo.emp_sessions
    (client_id, emp_id, session_start, session_end, minutes_worked, in_door, out_door, any_remote)
  SELECT client_id, emp_id, session_start, session_end, minutes_worked, in_door, out_door, any_remote
  FROM #final;
END
GO

