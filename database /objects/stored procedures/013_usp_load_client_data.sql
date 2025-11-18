
/****** Object:  StoredProcedure [dbo].[usp_load_client_data]    Script Date: 16/11/2025 12:06:54 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.usp_load_client_data', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_load_client_data;
GO


CREATE OR ALTER PROCEDURE [dbo].[usp_load_client_data]
  @client_id NVARCHAR(50),
  @attendance_csv_path NVARCHAR(4000),
  @has_header BIT = 1,
  @row_terminator NVARCHAR(10) = N'\n',
  @in_fallback_time  TIME(0) = '09:00',
  @out_fallback_time TIME(0) = '17:00',

  -- NEW: CSV date format hint. Values: 'auto' | 'yyyy-mm-dd' | 'mm/dd/yyyy' | 'dd/mm/yyyy' | 'dd.mm.yyyy' | 'dd-mm-yyyy'
  @date_format NVARCHAR(20) = N'auto',

  -- Calendar / windows
  @calendar_work_threshold_pct INT = NULL,
  @window_baseline_pct INT = NULL,

  -- Session thresholds (operational)
  @short_session_minutes INT = NULL,
  @odd_min_minutes       INT = NULL,
  @odd_max_minutes       INT = NULL,
  @long_day_minutes      INT = NULL,
  @late_start_hhmm       NVARCHAR(5) = NULL,

  -- Flight risk weights
  @flight_w_drop   FLOAT = NULL,
  @flight_w_short  FLOAT = NULL,
  @flight_w_streak FLOAT = NULL,
  @flight_scale_min_recent_days INT = NULL,

  -- Integrity risk weights
  @integrity_w_odd  FLOAT = NULL,
  @integrity_w_door FLOAT = NULL,
  @integrity_w_ping FLOAT = NULL,

  -- Workload risk weights & bonus
  @workload_w_long          FLOAT = NULL,
  @workload_w_late          FLOAT = NULL,
  @workload_bonus_points    FLOAT = NULL,
  @workload_bonus_delta_pct FLOAT = NULL
AS
BEGIN
  SET NOCOUNT ON;

  ---------------------------------------------------------------------------
  -- 0) Safety: clear any prior rows for @client_id so this is idempotent
  ---------------------------------------------------------------------------
  DELETE FROM dbo.report_flight      WHERE client_id=@client_id;
  DELETE FROM dbo.report_integrity   WHERE client_id=@client_id;
  DELETE FROM dbo.report_workload    WHERE client_id=@client_id;
  DELETE FROM dbo.calculated_data    WHERE client_id=@client_id;
  DELETE FROM dbo.work_calendar_dept WHERE client_id=@client_id;
  DELETE FROM dbo.work_calendar      WHERE client_id=@client_id;
  DELETE FROM dbo.legit_abs_blocks	 WHERE client_id=@client_id;
  DELETE FROM dbo.emp_day_legit      WHERE client_id=@client_id;
  DELETE FROM dbo.emp_sessions       WHERE client_id=@client_id;
  DELETE FROM dbo.attendance_rejects WHERE client_id=@client_id;
  DELETE FROM dbo.attendance         WHERE client_id=@client_id;
  DELETE FROM dbo.emp_work_calendar  WHERE client_id=@client_id;

  ---------------------------------------------------------------------------
  -- 1) Staging: raw CSV → #raw (all NVARCHAR). Expect columns in this order:
  --    client_id, emp_id, event_date, event_time, site_name, department,
  --    emp_role, badge_id, door_id
  ---------------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#raw') IS NOT NULL DROP TABLE #raw;
  CREATE TABLE #raw(
    t1 NVARCHAR(2000) NULL,  -- client_id
    t2 NVARCHAR(2000) NULL,  -- emp_id
    t3 NVARCHAR(2000) NULL,  -- event_date (text)
    t4 NVARCHAR(2000) NULL,  -- event_time (text)
    t5 NVARCHAR(2000) NULL,  -- site_name
    t6 NVARCHAR(2000) NULL,  -- department
    t7 NVARCHAR(2000) NULL,  -- emp_role
    t8 NVARCHAR(2000) NULL,  -- badge_id
    t9 NVARCHAR(2000) NULL   -- door_id
  );

  DECLARE @sql NVARCHAR(MAX) =
    N'BULK INSERT #raw
       FROM ' + QUOTENAME(@attendance_csv_path,'''') + N'
       WITH (
         DATAFILETYPE = ''char'',
         CODEPAGE = ''65001'',
         FIELDTERMINATOR = '','',
         ROWTERMINATOR   = ' + QUOTENAME(@row_terminator,'''') + N',
         KEEPNULLS,
         TABLOCK' +
         CASE WHEN @has_header=1 THEN N', FIRSTROW = 2' ELSE N'' END + N'
       );';

  EXEC sys.sp_executesql @sql;

  ---------------------------------------------------------------------------
  -- 2) Normalize/parse → #parsed
  --    - Trim spaces
  --    - Parse event_date using @date_format (with 'auto' fallback)
  --    - Keep raw values for rejects logging
  ---------------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#parsed') IS NOT NULL DROP TABLE #parsed;
  CREATE TABLE #parsed(
    client_id NVARCHAR(50) NOT NULL,
    emp_id NVARCHAR(50) NOT NULL,
    raw_event_date NVARCHAR(2000) NULL,
    raw_event_time NVARCHAR(2000) NULL,
    parsed_event_date DATE NULL,
    parsed_event_time TIME(0) NULL,
    site_name NVARCHAR(200) NULL,
    department NVARCHAR(200) NULL,
    emp_role NVARCHAR(200) NULL,
    badge_id NVARCHAR(200) NULL,
    door_id NVARCHAR(200) NULL
  );

  INSERT INTO #parsed(client_id, emp_id, raw_event_date, raw_event_time,
                      parsed_event_date, parsed_event_time, site_name,
                      department, emp_role, badge_id, door_id)
  SELECT
    LTRIM(RTRIM(ISNULL(t1,@client_id))) AS client_id,
    LTRIM(RTRIM(t2)) AS emp_id,
    LTRIM(RTRIM(t3)) AS raw_event_date,
    LTRIM(RTRIM(t4)) AS raw_event_time,

    /* ---- DATE PARSE (format-aware) ---- */
    CASE
      WHEN @date_format = N'yyyy-mm-dd' THEN TRY_CONVERT(date, t3, 23)
      WHEN @date_format = N'mm/dd/yyyy' THEN TRY_CONVERT(date, t3, 101)
      WHEN @date_format = N'dd/mm/yyyy' THEN TRY_CONVERT(date, t3, 103)
      WHEN @date_format = N'dd.mm.yyyy' THEN TRY_CONVERT(date, t3, 104)
      WHEN @date_format = N'dd-mm-yyyy' THEN TRY_CONVERT(date, t3, 105)

      WHEN @date_format = N'auto' THEN
        CASE
          WHEN t3 LIKE N'____-__-__' OR t3 LIKE N'____-_-__' OR t3 LIKE N'____-__-_' OR t3 LIKE N'____-_-_' THEN
               TRY_CONVERT(date, t3, 23)  -- yyyy-mm-dd
          WHEN t3 LIKE N'%/%' THEN
               /* prefer US first to avoid MM/DD vs DD/MM swaps; if fails, try EU */
               COALESCE(TRY_CONVERT(date, t3, 101), TRY_CONVERT(date, t3, 103))
          WHEN t3 LIKE N'%.%' THEN
               TRY_CONVERT(date, t3, 104) -- dd.mm.yyyy
          ELSE
               COALESCE(
                 TRY_CONVERT(date, t3, 23),   -- yyyy-mm-dd
                 TRY_CONVERT(date, t3, 101),  -- mm/dd/yyyy
                 TRY_CONVERT(date, t3, 103),  -- dd/mm/yyyy
                 TRY_CONVERT(date, t3, 104),  -- dd.mm.yyyy
                 TRY_CONVERT(date, t3, 105)   -- dd-mm-yyyy
               )
        END
      ELSE NULL
    END AS parsed_event_date,

    /* ---- TIME PARSE (tolerant: HH:mm or HH:mm:ss) ---- */
    COALESCE(
      TRY_CONVERT(time(0), t4, 108),      -- HH:mm:ss
      TRY_CONVERT(time(0), t4)            -- HH:mm
    ) AS parsed_event_time,

    NULLIF(LTRIM(RTRIM(t5)),N'') AS site_name,
    NULLIF(LTRIM(RTRIM(t6)),N'') AS department,
    NULLIF(LTRIM(RTRIM(t7)),N'') AS emp_role,
    NULLIF(LTRIM(RTRIM(t8)),N'') AS badge_id,
    NULLIF(LTRIM(RTRIM(t9)),N'') AS door_id
  FROM #raw;

  ---------------------------------------------------------------------------
  -- 3) Guard: log rows with an unparseable DATE into dbo.attendance_rejects,
  --           then remove them from the pipeline so they won't enter attendance.
  --           (Static schema: client_id, raw_line, reason, created_at DEFAULT)
  ---------------------------------------------------------------------------
  IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.attendance_rejects') AND type = 'U')
  BEGIN
    INSERT INTO dbo.attendance_rejects (client_id, raw_line, reason)
    SELECT
      @client_id,
      -- Reconstruct a CSV-like line (same column order as your file)
      -- client_id, emp_id, event_date, event_time, site_name, department, emp_role, badge_id, door_id
      CONCAT_WS(
        N',',
        ISNULL(@client_id, N''),
        ISNULL(p.emp_id, N''),
        ISNULL(p.raw_event_date, N''),
        ISNULL(p.raw_event_time, N''),
        ISNULL(p.site_name, N''),
        ISNULL(p.department, N''),
        ISNULL(p.emp_role, N''),
        ISNULL(p.badge_id, N''),
        ISNULL(p.door_id, N'')
      ) AS raw_line,
      N'Unparseable date'
    FROM #parsed p
    WHERE p.parsed_event_date IS NULL
  END

  -- Optional: reject rows with bad time parsing
  IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.attendance_rejects') AND type = 'U')
  BEGIN
    INSERT INTO dbo.attendance_rejects (client_id, raw_line, reason)
    SELECT
      @client_id,
      CONCAT_WS(
        N',',
        ISNULL(@client_id, N''),
        ISNULL(p.emp_id, N''),
        ISNULL(p.raw_event_date, N''),
        ISNULL(p.raw_event_time, N''),
        ISNULL(p.site_name, N''),
        ISNULL(p.department, N''),
        ISNULL(p.emp_role, N''),
        ISNULL(p.badge_id, N''),
        ISNULL(p.door_id, N'')
      ),
      N'Unparseable time'
    FROM #parsed p
    WHERE p.parsed_event_date IS NOT NULL
      AND p.parsed_event_time IS NULL;
  END

  DELETE p
  FROM #parsed p
  WHERE p.parsed_event_date IS NOT NULL
    AND p.parsed_event_time IS NULL;


  -- Remove the unparseable rows from the pipeline regardless
  DELETE p
  FROM #parsed p
  WHERE p.parsed_event_date IS NULL;

  ---------------------------------------------------------------------------
  -- 4) Insert normalized rows into dbo.attendance
  ---------------------------------------------------------------------------
  INSERT INTO dbo.attendance
    (client_id, emp_id, event_date, event_time, site_name, department, emp_role, badge_id, door_id)
  SELECT
    @client_id,
    p.emp_id,
    p.parsed_event_date,
    p.parsed_event_time,
    ISNULL(p.site_name,   N''),
    ISNULL(p.department, N''),
    ISNULL(p.emp_role,  N''),
    ISNULL(p.badge_id,  N''),
    ISNULL(p.door_id,   N'')
  FROM #parsed p;

  ---------------------------------------------------------------------------
  -- 5) Apply non-NULL overrides into risk_config (simple upsert without MERGE)
  ---------------------------------------------------------------------------
  DECLARE @cfg TABLE (config_key NVARCHAR(100) NOT NULL, config_value NVARCHAR(200) NOT NULL, PRIMARY KEY(config_key));

  -- collect only provided (non-NULL) knobs
  IF @calendar_work_threshold_pct IS NOT NULL INSERT INTO @cfg VALUES (N'calendar_work_threshold_pct', CONVERT(NVARCHAR(200),@calendar_work_threshold_pct));
  IF @window_baseline_pct          IS NOT NULL INSERT INTO @cfg VALUES (N'window_baseline_pct',          CONVERT(NVARCHAR(200),@window_baseline_pct));

  IF @short_session_minutes IS NOT NULL INSERT INTO @cfg VALUES (N'short_session_minutes', CONVERT(NVARCHAR(200),@short_session_minutes));
  IF @odd_min_minutes       IS NOT NULL INSERT INTO @cfg VALUES (N'odd_min_minutes',       CONVERT(NVARCHAR(200),@odd_min_minutes));
  IF @odd_max_minutes       IS NOT NULL INSERT INTO @cfg VALUES (N'odd_max_minutes',       CONVERT(NVARCHAR(200),@odd_max_minutes));
  IF @long_day_minutes      IS NOT NULL INSERT INTO @cfg VALUES (N'long_day_minutes',      CONVERT(NVARCHAR(200),@long_day_minutes));
  IF @late_start_hhmm       IS NOT NULL INSERT INTO @cfg VALUES (N'late_start_hhmm',       CONVERT(NVARCHAR(200),@late_start_hhmm));

  IF @flight_w_drop   IS NOT NULL INSERT INTO @cfg VALUES (N'flight_w_drop',   CONVERT(NVARCHAR(200),@flight_w_drop));
  IF @flight_w_short  IS NOT NULL INSERT INTO @cfg VALUES (N'flight_w_short',  CONVERT(NVARCHAR(200),@flight_w_short));
  IF @flight_w_streak IS NOT NULL INSERT INTO @cfg VALUES (N'flight_w_streak', CONVERT(NVARCHAR(200),@flight_w_streak));
  IF @flight_scale_min_recent_days IS NOT NULL INSERT INTO @cfg VALUES (N'flight_scale_min_recent_days', CONVERT(NVARCHAR(200),@flight_scale_min_recent_days));

  IF @integrity_w_odd  IS NOT NULL INSERT INTO @cfg VALUES (N'integrity_w_odd',  CONVERT(NVARCHAR(200),@integrity_w_odd));
  IF @integrity_w_door IS NOT NULL INSERT INTO @cfg VALUES (N'integrity_w_door', CONVERT(NVARCHAR(200),@integrity_w_door));
  IF @integrity_w_ping IS NOT NULL INSERT INTO @cfg VALUES (N'integrity_w_ping', CONVERT(NVARCHAR(200),@integrity_w_ping));

  IF @workload_w_long          IS NOT NULL INSERT INTO @cfg VALUES (N'workload_w_long',          CONVERT(NVARCHAR(200),@workload_w_long));
  IF @workload_w_late          IS NOT NULL INSERT INTO @cfg VALUES (N'workload_w_late',          CONVERT(NVARCHAR(200),@workload_w_late));
  IF @workload_bonus_points    IS NOT NULL INSERT INTO @cfg VALUES (N'workload_bonus_points',    CONVERT(NVARCHAR(200),@workload_bonus_points));
  IF @workload_bonus_delta_pct IS NOT NULL INSERT INTO @cfg VALUES (N'workload_bonus_delta_pct', CONVERT(NVARCHAR(200),@workload_bonus_delta_pct));

  -- UPDATE existing keys
  UPDATE rc
    SET rc.config_value = c.config_value
  FROM dbo.risk_config rc
  JOIN @cfg c ON rc.client_id=@client_id AND rc.config_key=c.config_key;

  -- INSERT missing keys
  INSERT INTO dbo.risk_config (client_id, config_key, config_value)
  SELECT @client_id, c.config_key, c.config_value
  FROM @cfg c
  LEFT JOIN dbo.risk_config rc
         ON rc.client_id=@client_id AND rc.config_key=c.config_key
  WHERE rc.client_id IS NULL;

-- downstream pipeline (safe order)
EXEC dbo.sp_calc_sessions           @client_id=@client_id, @in_fallback_time=@in_fallback_time, @out_fallback_time=@out_fallback_time;
EXEC dbo.sp_infer_work_calendar     @client_id=@client_id;
EXEC dbo.sp_build_dept_calendar     @client_id=@client_id;
EXEC dbo.sp_detect_legit_absences   @client_id=@client_id;

-- NOW build emp-specific working days from the finalized windows
EXEC dbo.sp_build_emp_work_calendar @client_id=@client_id;

-- build metrics first
EXEC dbo.sp_calc_metrics            @client_id=@client_id;
EXEC dbo.sp_update_adjusted_metrics @client_id=@client_id;

-- reports that only read
EXEC dbo.sp_report_flight           @client_id=@client_id;
EXEC dbo.sp_report_integrity        @client_id=@client_id;
EXEC dbo.sp_report_workload         @client_id=@client_id;
    ---------------------------------------------------------------------------
  -- 7) Summary (light)
  ---------------------------------------------------------------------------
  DECLARE @min_d DATE, @max_d DATE, @rows INT;
  SELECT @min_d = MIN(event_date), @max_d = MAX(event_date), @rows = COUNT(*)
  FROM dbo.attendance WHERE client_id=@client_id;

  SELECT
    client_id    = @client_id,
    loaded_rows  = @rows,
    date_min     = @min_d,
    date_max     = @max_d;
END
GO

