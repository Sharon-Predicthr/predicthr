SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_load_client_data_v2]
(
  @client_id NVARCHAR(50),

  -- MODE A: LOCAL FILE (כמו היום)
  @attendance_csv_path NVARCHAR(4000) = NULL,

  -- MODE B: HYBRID (טעינה מ־attendance_staging)
  @batch_id UNIQUEIDENTIFIER = NULL,

  @has_header BIT = 1,
  @row_terminator NVARCHAR(10) = N'\n',  -- נשאר לפרמטר תאורטי, בפועל אנחנו משתמשים ב־0x0A

  @in_fallback_time  TIME(0) = '09:00',
  @out_fallback_time TIME(0) = '17:00',

  -- CSV date format hint
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
)
AS
BEGIN
  SET NOCOUNT ON;

  ---------------------------------------------------------------------------
  -- 0) MODE SELECTION: local file (A) vs hybrid batch (B)
  ---------------------------------------------------------------------------
  IF @attendance_csv_path IS NULL AND @batch_id IS NULL
    THROW 51000, 'You must provide either @attendance_csv_path (local mode) or @batch_id (hybrid mode).', 1;

  IF @attendance_csv_path IS NOT NULL AND @batch_id IS NOT NULL
    THROW 51001, 'Provide ONLY ONE of @attendance_csv_path OR @batch_id (not both).', 1;

  ---------------------------------------------------------------------------
  -- 1) Safety: clear any prior rows for @client_id so this is idempotent
  ---------------------------------------------------------------------------
  DELETE FROM dbo.report_flight      WHERE client_id=@client_id;
  DELETE FROM dbo.report_fraud       WHERE client_id=@client_id;
  DELETE FROM dbo.report_burnout     WHERE client_id=@client_id;
  DELETE FROM dbo.calculated_data    WHERE client_id=@client_id;
  DELETE FROM dbo.work_calendar_dept WHERE client_id=@client_id;
  DELETE FROM dbo.work_calendar      WHERE client_id=@client_id;
  -- DELETE FROM dbo.legit_abs_blocks	 WHERE client_id=@client_id;
  -- DELETE FROM dbo.emp_day_legit      WHERE client_id=@client_id;
  DELETE FROM dbo.emp_sessions       WHERE client_id=@client_id;
  DELETE FROM dbo.attendance_rejects WHERE client_id=@client_id;
  DELETE FROM dbo.attendance         WHERE client_id=@client_id;
  DELETE FROM dbo.emp_work_calendar  WHERE client_id=@client_id;

  ---------------------------------------------------------------------------
  -- 2) RAW STAGE: #raw  (טבלת עבודה זמנית – כמו אצלך)
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
    t9 NVARCHAR(2000) NULL,   -- door_id
    t10 NVARCHAR(2000) NULL   -- source_type
  );

  ---------------------------------------------------------------------------
  -- 2A) MODE A: LOCAL FILE → BULK INSERT INTO #raw
  ---------------------------------------------------------------------------
  IF @attendance_csv_path IS NOT NULL
  BEGIN
      -- Create temporary table with 9 columns for BULK INSERT (CSV has 9 columns)
      IF OBJECT_ID('tempdb..#bulk_temp') IS NOT NULL DROP TABLE #bulk_temp;
      CREATE TABLE #bulk_temp(
        t1 NVARCHAR(2000) NULL,
        t2 NVARCHAR(2000) NULL,
        t3 NVARCHAR(2000) NULL,
        t4 NVARCHAR(2000) NULL,
        t5 NVARCHAR(2000) NULL,
        t6 NVARCHAR(2000) NULL,
        t7 NVARCHAR(2000) NULL,
        t8 NVARCHAR(2000) NULL,
        t9 NVARCHAR(2000) NULL
      );

      DECLARE @sql NVARCHAR(MAX) =
           N'BULK INSERT #bulk_temp
             FROM ' + QUOTENAME(@attendance_csv_path,'''') + N'
             WITH (
               DATAFILETYPE = ''char'',
               FIELDTERMINATOR = '','',
               ROWTERMINATOR  = ''0x0A'',   -- LF, מתאים גם ל־Linux וגם ל־Windows (CRLF גם מזוהה)
               KEEPNULLS,
               MAXERRORS = 0,
               FIRSTROW = ' + CAST(CASE WHEN @has_header = 1 THEN 2 ELSE 1 END AS NVARCHAR(10)) + N'
             );';

      EXEC sys.sp_executesql @sql;

      -- Copy from temp table to #raw, setting t10 to NULL
      INSERT INTO #raw(t1, t2, t3, t4, t5, t6, t7, t8, t9, t10)
      SELECT t1, t2, t3, t4, t5, t6, t7, t8, t9, NULL
      FROM #bulk_temp;

      DROP TABLE #bulk_temp;
  END

  ---------------------------------------------------------------------------
  -- 2B) MODE B: HYBRID → לוקחים מה־staging
  ---------------------------------------------------------------------------
  IF @batch_id IS NOT NULL
  BEGIN
      IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.attendance_staging') AND type = 'U')
          THROW 51002, 'attendance_staging table not found (hybrid mode requires it).', 1;

      INSERT INTO #raw(t1,t2,t3,t4,t5,t6,t7,t8,t9,t10)
      SELECT
          s.t1,s.t2,s.t3,s.t4,s.t5,s.t6,s.t7,s.t8,s.t9,s.t10
      FROM dbo.attendance_staging s
      WHERE s.batch_id = @batch_id
        AND s.client_id = @client_id
      ORDER BY s.row_number;

      IF @@ROWCOUNT = 0
          THROW 51003, 'No rows found in attendance_staging for given @batch_id and @client_id.', 1;

      -- ניקוי ה־staging לבאטצ׳ הזה (כדי לא לצבור זבל)
      DELETE FROM dbo.attendance_staging
      WHERE batch_id = @batch_id
        AND client_id = @client_id;
  END

  ---------------------------------------------------------------------------
  -- 3) Normalize/parse → #parsed   (אותו קוד שהיה אצלך)
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
    door_id NVARCHAR(200) NULL,
    source_type SMALLINT NULL
  );

  INSERT INTO #parsed(client_id, emp_id, raw_event_date, raw_event_time,
                      parsed_event_date, parsed_event_time, site_name,
                      department, emp_role, badge_id, door_id, source_type)
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
    NULLIF(LTRIM(RTRIM(t9)),N'') AS door_id,
    NULLIF(LTRIM(RTRIM(t10)),N'') AS source_type
  FROM #raw;

  ---------------------------------------------------------------------------
  -- 4) Log rejects (DATE/TIME) → attendance_rejects
  ---------------------------------------------------------------------------
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
        ISNULL(p.door_id, N''),
        ISNULL(p.source_type, N'')
      ) AS raw_line,
      N'Unparseable date'
    FROM #parsed p
    WHERE p.parsed_event_date IS NULL;

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
        ISNULL(p.door_id, N''),
        ISNULL(p.source_type, N'')
      ),
      N'Unparseable time'
    FROM #parsed p
    WHERE p.parsed_event_date IS NOT NULL
      AND p.parsed_event_time IS NULL;
  END

  -- drop rows עם TIME לא תקין
  DELETE p
  FROM #parsed p
  WHERE p.parsed_event_date IS NOT NULL
    AND p.parsed_event_time IS NULL;

  -- drop rows עם DATE לא תקין
  DELETE p
  FROM #parsed p
  WHERE p.parsed_event_date IS NULL;

  ---------------------------------------------------------------------------
  -- 5) Insert normalized rows into dbo.attendance
  ---------------------------------------------------------------------------
  INSERT INTO dbo.attendance
    (client_id, emp_id, event_date, event_time, site_name, department, emp_role, badge_id, door_id, source_type)
  SELECT
    @client_id,
    p.emp_id,
    p.parsed_event_date,
    p.parsed_event_time,
    ISNULL(p.site_name,   N''),
    ISNULL(p.department,  N''),
    ISNULL(p.emp_role,    N''),
    ISNULL(p.badge_id,    N''),
    ISNULL(p.door_id,     N''),
    ISNULL(p.source_type, N'')
  FROM #parsed p;

  ---------------------------------------------------------------------------
  -- 6) risk_config overrides (אותו קוד שיש אצלך)
  ---------------------------------------------------------------------------
  DECLARE @cfg TABLE (
      config_key   NVARCHAR(100) NOT NULL,
      config_value NVARCHAR(200) NOT NULL,
      PRIMARY KEY(config_key)
  );

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

  -- UPDATE
  UPDATE rc
    SET rc.config_value = c.config_value
  FROM dbo.risk_config rc
  JOIN @cfg c ON rc.client_id=@client_id AND rc.config_key=c.config_key;

  -- INSERT missing
  INSERT INTO dbo.risk_config (client_id, config_key, config_value)
  SELECT @client_id, c.config_key, c.config_value
  FROM @cfg c
  LEFT JOIN dbo.risk_config rc
         ON rc.client_id=@client_id AND rc.config_key=c.config_key
  WHERE rc.client_id IS NULL;

  ---------------------------------------------------------------------------
  -- 7) Downstream pipeline (אותו סדר בטוח כמו אצלך)
  ---------------------------------------------------------------------------
  EXEC dbo.usp_calc_sessions           @client_id=@client_id, @in_fallback_time=@in_fallback_time, @out_fallback_time=@out_fallback_time;
  EXEC dbo.usp_infer_work_calendar     @client_id=@client_id;
  EXEC dbo.usp_build_dept_calendar     @client_id=@client_id;
  -- EXEC dbo.usp_detect_legit_absences   @client_id=@client_id;

  EXEC dbo.usp_build_emp_work_calendar @client_id=@client_id;

  EXEC dbo.usp_calc_metrics            @client_id=@client_id;
  EXEC dbo.usp_calc_periods            @client_id=@client_id;
  EXEC dbo.usp_update_adjusted_metrics @client_id=@client_id;

  EXEC dbo.usp_calc_flight_risk_score   @client_id=@client_id;
  EXEC dbo.usp_calc_fraud_risk_score    @client_id=@client_id;
  EXEC dbo.usp_calc_burnout_risk_score  @client_id=@client_id;

  ---------------------------------------------------------------------------
  -- 8) Summary
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
