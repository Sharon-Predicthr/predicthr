USE [HR_v10]
GO

/****** Object:  StoredProcedure [dbo].[001_init_schema]    Script Date: 16/11/2025 11:56:15 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[001_init_schema]
AS
BEGIN
  SET NOCOUNT ON;

------------------------------------------------------------
-- Drop dependent procedures
------------------------------------------------------------
IF OBJECT_ID('dbo.usp_report_sessions','P')      IS NOT NULL DROP PROCEDURE dbo.usp_report_sessions;
IF OBJECT_ID('dbo.usp_report_workload','P')      IS NOT NULL DROP PROCEDURE dbo.usp_report_workload;
IF OBJECT_ID('dbo.usp_report_integrity','P')     IS NOT NULL DROP PROCEDURE dbo.usp_report_integrity;
IF OBJECT_ID('dbo.usp_report_flight','P')        IS NOT NULL DROP PROCEDURE dbo.usp_report_flight;
IF OBJECT_ID('dbo.usp_report_window','P')        IS NOT NULL DROP PROCEDURE dbo.usp_report_window;
IF OBJECT_ID('dbo.usp_calc_metrics','P')         IS NOT NULL DROP PROCEDURE dbo.usp_calc_metrics;
IF OBJECT_ID('dbo.usp_calc_sessions','P')        IS NOT NULL DROP PROCEDURE dbo.usp_calc_sessions;
IF OBJECT_ID('dbo.usp_infer_work_calendar','P')  IS NOT NULL DROP PROCEDURE dbo.usp_infer_work_calendar;
IF OBJECT_ID('dbo.usp_load_client_data','P')     IS NOT NULL DROP PROCEDURE dbo.usp_load_client_data;

------------------------------------------------------------
-- Drop tables (child -> parent). Make sure to drop the right ones.
------------------------------------------------------------
IF OBJECT_ID('dbo.work_calendar_dept','U') IS NOT NULL DROP TABLE dbo.work_calendar_dept;
IF OBJECT_ID('dbo.emp_day_legit','U')      IS NOT NULL DROP TABLE dbo.emp_day_legit;
IF OBJECT_ID('dbo.legit_abs_blocks','U')   IS NOT NULL DROP TABLE dbo.legit_abs_blocks;
IF OBJECT_ID('dbo.report_workload','U')    IS NOT NULL DROP TABLE dbo.report_workload;
IF OBJECT_ID('dbo.report_integrity','U')   IS NOT NULL DROP TABLE dbo.report_integrity;
IF OBJECT_ID('dbo.report_flight','U')      IS NOT NULL DROP TABLE dbo.report_flight;
IF OBJECT_ID('dbo.risk_interventions','U') IS NOT NULL DROP TABLE dbo.risk_interventions;
IF OBJECT_ID('dbo.interventions','U')      IS NOT NULL DROP TABLE dbo.interventions;
IF OBJECT_ID('dbo.risk_config','U')        IS NOT NULL DROP TABLE dbo.risk_config;
IF OBJECT_ID('dbo.calculated_data','U')    IS NOT NULL DROP TABLE dbo.calculated_data;
IF OBJECT_ID('dbo.work_calendar','U')      IS NOT NULL DROP TABLE dbo.work_calendar;
IF OBJECT_ID('dbo.emp_sessions','U')       IS NOT NULL DROP TABLE dbo.emp_sessions;
IF OBJECT_ID('dbo.attendance_rejects','U') IS NOT NULL DROP TABLE dbo.attendance_rejects;
IF OBJECT_ID('dbo.emp_work_calendar','U')  IS NOT NULL DROP TABLE dbo.emp_work_calendar; -- <-- fixed
IF OBJECT_ID('dbo.attendance','U')         IS NOT NULL DROP TABLE dbo.attendance;        -- drop attendance once, at the end if others depend on it

------------------------------------------------------------
-- attendance
------------------------------------------------------------
CREATE TABLE dbo.attendance
(
  client_id   NVARCHAR(50)  NOT NULL,
  emp_id      NVARCHAR(100) NOT NULL,
  event_date  DATE          NOT NULL,
  event_time  TIME(0)       NOT NULL,
  site_name   NVARCHAR(200)  NULL,
  department  NVARCHAR(200) NOT NULL DEFAULT(N'Not Reported'),
  emp_role    NVARCHAR(200) NOT NULL DEFAULT(N'Not Reported'),
  badge_id    NVARCHAR(200) NULL,
  door_id     NVARCHAR(200) NULL
);

CREATE INDEX IX_attendance_client_emp_date
  ON dbo.attendance(client_id, emp_id, event_date)
  INCLUDE(event_time, door_id);

CREATE INDEX IX_attendance_client_date_dept
  ON dbo.attendance(client_id, event_date)
  INCLUDE(emp_id, department);

  /* attendance_rejects */
  CREATE TABLE dbo.attendance_rejects
  (
    client_id  NVARCHAR(50)  NOT NULL,
    raw_line   NVARCHAR(MAX) NOT NULL,
    reason     NVARCHAR(400) NOT NULL,
    created_at DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
  );

  /* emp_sessions */
  CREATE TABLE dbo.emp_sessions
  (
    client_id      NVARCHAR(50)  NOT NULL,
    emp_id         NVARCHAR(100) NOT NULL,
    session_start  DATETIME2(0)  NOT NULL,
    session_end    DATETIME2(0)  NOT NULL,
    minutes_worked INT           NOT NULL,
    in_door        NVARCHAR(200) NULL,
    out_door       NVARCHAR(200) NULL,
    any_remote     BIT           NOT NULL DEFAULT(0),
    PRIMARY KEY (client_id, emp_id, session_start)
  );
  CREATE INDEX IX_emp_sessions_client_emp_date
    ON dbo.emp_sessions(client_id, emp_id, session_start)
    INCLUDE(session_end, minutes_worked, in_door, out_door, any_remote);

  CREATE INDEX IX_sessions_client_date_emp
	ON dbo.emp_sessions(client_id, session_start) INCLUDE(emp_id);

  /* global level work_calendar */
  CREATE TABLE dbo.work_calendar
  (
    client_id        NVARCHAR(50) NOT NULL,
    calendar_date    DATE         NOT NULL,
    is_workday       BIT          NOT NULL,
    present_emp      INT          NOT NULL,
    active_emp       INT          NOT NULL,
    coverage_pct     FLOAT        NOT NULL,
    detection_method NVARCHAR(50) NOT NULL,
    computed_at      DATETIME2(0) NOT NULL,
    day_of_week      NVARCHAR(20) NOT NULL,
    PRIMARY KEY (client_id, calendar_date)
  );
  CREATE INDEX IX_work_calendar_client_date
	ON dbo.work_calendar(client_id, calendar_date) ;

   /* employee level work_calendar */
  CREATE TABLE dbo.emp_work_calendar
  (
    client_id      NVARCHAR(50)   NOT NULL,
    emp_id         NVARCHAR(100)  NOT NULL,
    calendar_date  DATE           NOT NULL,
    is_working     BIT            NOT NULL,   -- 1 = expected to work that day, 0 = not expected
    source_reason  NVARCHAR(80)   NULL,       -- e.g., 'baseline_weekday_pattern','recent_presence','company_off','legit_absence','pre_first_seen','post_last_seen'
    computed_at    DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_emp_work_calendar PRIMARY KEY (client_id, emp_id, calendar_date)
  );

  CREATE INDEX IX_emp_work_calendar_emp ON dbo.emp_work_calendar(emp_id, calendar_date);


  /* calculated_data (employee-level metrics used by all reports) */
  CREATE TABLE dbo.calculated_data
  (
    client_id        NVARCHAR(50)  NOT NULL,
    emp_id           NVARCHAR(100) NOT NULL,
    department       NVARCHAR(200) ,
    emp_role         NVARCHAR(200) ,
    site_name        NVARCHAR(200) ,

    baseline_start   DATE          NOT NULL,
    baseline_end     DATE          NOT NULL,
    baseline_days    INT           NOT NULL,
    recent_start     DATE          NOT NULL,
    recent_end       DATE          NOT NULL,
    recent_days      INT          NOT NULL,

    pres_b           INT           NOT NULL,
    pres_r           INT           NOT NULL,
    pres_b_norm      FLOAT         NOT NULL,
    pres_r_norm      FLOAT         NOT NULL,

    max_off_run       INT          NOT NULL,
    short_gap_count_r INT          NOT NULL,

    long_r            FLOAT        NOT NULL,
    late_r            FLOAT        NOT NULL,
    avg_min_b         FLOAT        NULL,
    avg_min_r         FLOAT        NULL,

    odd_pct_r         FLOAT        NOT NULL,
    door_mis_pct_r    FLOAT        NOT NULL,
    pingpong_pct_r    FLOAT        NOT NULL,

    /* >>> NEW: static aliases the reports expect (no SP changes needed) */
    odd_pct_recent              AS (odd_pct_r) PERSISTED,
    door_mismatch_pct_recent   AS (door_mis_pct_r) PERSISTED,
    pingpong_pct_recent        AS (pingpong_pct_r) PERSISTED,

    pres_b_norm_adj       FLOAT  NULL,
    pres_r_norm_adj       FLOAT  NULL,
    max_off_run_adj       INT    NULL,
    short_gap_count_r_adj INT    NULL,
    legit_abs_days_b      INT    NULL,
    legit_abs_days_r      INT    NULL,
    legit_abs_conf_avg_r  FLOAT  NULL,  -- 0..1 average confidence on recent legit days

    CONSTRAINT PK_calculated_data PRIMARY KEY (client_id, emp_id)
  );
  CREATE UNIQUE INDEX UX_calculated_data_client_emp
    ON dbo.calculated_data(client_id, emp_id);

  /* interventions */
  CREATE TABLE dbo.interventions
  (
    intervention_id  INT IDENTITY(1,1) PRIMARY KEY,
    short_text       NVARCHAR(200)  NOT NULL,
    long_description NVARCHAR(2000) NOT NULL,
    is_active        BIT            NOT NULL DEFAULT(1)
  );

  /* risk_interventions */
  CREATE TABLE dbo.risk_interventions
  (
    risk_type       NVARCHAR(40)  NOT NULL,  /* 'flight' | 'integrity' | 'workload' */
    min_score       INT           NOT NULL,
    max_score       INT           NOT NULL,
    intervention_id INT           NOT NULL,
    priority        INT           NOT NULL DEFAULT(1),
    is_active       BIT           NOT NULL DEFAULT(1)
  );
  CREATE INDEX IX_risk_interventions_risk_range
    ON dbo.risk_interventions(risk_type, min_score, max_score, priority)
    INCLUDE(intervention_id, is_active);

  /* risk_config */
  CREATE TABLE dbo.risk_config
  (
    client_id    NVARCHAR(50)  NULL,
    config_key   NVARCHAR(100) NOT NULL,
    config_value NVARCHAR(400) NOT NULL
  );
  CREATE UNIQUE INDEX UX_risk_config_client_key
    ON dbo.risk_config(client_id, config_key);

  /* ---- GLOBAL DEFAULTS (client_id = NULL) ---- */
  INSERT INTO dbo.risk_config(client_id, config_key, config_value) VALUES
    (NULL, 'calendar_work_threshold_pct', '30'),
    (NULL, 'short_session_minutes',       '180'),
    (NULL, 'odd_min_minutes',             '10'),
    (NULL, 'odd_max_minutes',             '60'),
    (NULL, 'long_day_minutes',            '600'),
    (NULL, 'late_start_hhmm',             '10:00'),

    -- Flight
    (NULL, 'flight_w_drop',               '0.70'),
    (NULL, 'flight_w_short',              '0.10'),
    (NULL, 'flight_w_streak',             '0.20'),
    (NULL, 'flight_scale_min_recent_days','10'),
    (NULL, 'flight_intervention_min_score','15'),

    -- Integrity
    (NULL, 'integrity_w_odd',             '0.50'),
    (NULL, 'integrity_w_door',            '0.30'),
    (NULL, 'integrity_w_ping',            '0.20'),

    -- Workload
    (NULL, 'workload_w_long',             '0.60'),
    (NULL, 'workload_w_late',             '0.40'),
    (NULL, 'workload_bonus_points',       '5'),
    (NULL, 'workload_bonus_delta_pct',    '10'),
	(NULL,'integrity_intervention_min_score','15'),
	(NULL,'workload_intervention_min_score','15'),

    -- baseline vs. recent
	(NULL,N'window_baseline_pct','70'),
	(NULL,N'recent_min_days','20'),
	(NULL,N'recent_max_days','45'),
	(NULL,N'holiday_coverage_threshold_pct','15'),
	(NULL,N'dept_holiday_threshold_pct','25'),
	(NULL,N'pto_min_block_days','5'),
	(NULL,N'sick_max_block_days','3'),
	(NULL,N'legit_conf_full_exclude_min','0.6'),
	(NULL,N'legit_conf_partial_min','0.3'),
	(NULL,N'baseline_min_days','15');

  /* -------- Persistent report tables -------- */
  CREATE TABLE dbo.report_flight
  (
    client_id           NVARCHAR(50)  NOT NULL,
    emp_id              NVARCHAR(100) NOT NULL,
    department          NVARCHAR(200) NOT NULL,
    emp_role            NVARCHAR(200) NOT NULL,
	site_name			NVARCHAR(200) NOT NULL,
    risk_score          INT           NOT NULL,
    risk_type           NVARCHAR(40)  NOT NULL,
    intervention_id     INT           NULL,
    intervention_short  NVARCHAR(200) NULL,
    intervention_detail NVARCHAR(2000) NULL,
    priority            INT           NULL,
    score_explanation   NVARCHAR(600) NOT NULL,
    computed_at         DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_report_flight_client_score
    ON dbo.report_flight(client_id, risk_score DESC, emp_id);

  CREATE TABLE dbo.report_integrity
  (
    client_id           NVARCHAR(50)  NOT NULL,
    emp_id              NVARCHAR(100) NOT NULL,
    department          NVARCHAR(200) NOT NULL,
    emp_role            NVARCHAR(200) NOT NULL,
	site_name			NVARCHAR(200) NOT NULL,
    risk_score          INT           NOT NULL,
    risk_type           NVARCHAR(40)  NOT NULL,
    intervention_id     INT           NULL,
    intervention_short  NVARCHAR(200) NULL,
    intervention_detail NVARCHAR(2000) NULL,
    priority            INT           NULL,
    score_explanation   NVARCHAR(600) NOT NULL,
    computed_at         DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_report_integrity_client_score
    ON dbo.report_integrity(client_id, risk_score DESC, emp_id);

  CREATE TABLE dbo.report_workload
  (
    client_id           NVARCHAR(50)  NOT NULL,
    emp_id              NVARCHAR(100) NOT NULL,
    department          NVARCHAR(200) NOT NULL,
    emp_role            NVARCHAR(200) NOT NULL,
 	site_name			NVARCHAR(200) NOT NULL,
    risk_score          INT           NOT NULL,
    risk_type           NVARCHAR(40)  NOT NULL,
    intervention_id     INT           NULL,
    intervention_short  NVARCHAR(200) NULL,
    intervention_detail NVARCHAR(2000) NULL,
    priority            INT           NULL,
    score_explanation   NVARCHAR(600) NOT NULL,
    computed_at         DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_report_workload_client_score
    ON dbo.report_workload(client_id, risk_score DESC, emp_id);

/* ---------- NEW: Department-level work calendar ---------- */
 
CREATE TABLE dbo.work_calendar_dept
(
  client_id         NVARCHAR(50) NOT NULL,
  calendar_date     DATE         NOT NULL,
  department        NVARCHAR(200) NOT NULL,
  dept_present      INT          NOT NULL,
  dept_active       INT          NOT NULL,
  dept_coverage_pct FLOAT        NOT NULL,
  is_workday_dept   BIT          NOT NULL,
  computed_at       DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  PRIMARY KEY (client_id, calendar_date, department)
);
  CREATE INDEX IX_work_calendar_dept_client_calendar_department
    ON dbo.work_calendar_dept(client_id, calendar_date, department)
    INCLUDE(dept_present, dept_active, dept_coverage_pct, is_workday_dept);

/* ---------- NEW: Day-level legitimacy flags (per employee, per day) ---------- */

CREATE TABLE dbo.emp_day_legit
(
  client_id        NVARCHAR(50)  NOT NULL,
  emp_id           NVARCHAR(100) NOT NULL,
  calendar_date    DATE          NOT NULL,
  is_legit_absent  BIT           NOT NULL,   -- 1=legit block day (exclude/discount from penalties)
  inferred_reason  NVARCHAR(32)  NOT NULL,   -- 'vacation_like' | 'sick_like' | 'dept_off' | 'org_off' | 'partial_errand'
  confidence       FLOAT         NOT NULL,   -- 0..1
  source_note      NVARCHAR(100) NULL,       -- short detail (e.g., 'anchored_weekend', 'dept_coverage_14%')
  created_at       DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
  PRIMARY KEY (client_id, emp_id, calendar_date)
);
  CREATE INDEX IX_emp_day_legit_client_emp_calendar
    ON dbo.emp_day_legit(client_id, emp_id, calendar_date);

  CREATE INDEX IX_legit_date_emp
	ON dbo.emp_day_legit(client_id, calendar_date, emp_id);

/* ---------- Block-level ledger for explainability ---------- */

CREATE TABLE dbo.legit_abs_blocks
(
  client_id        NVARCHAR(50)  NOT NULL,
  emp_id           NVARCHAR(100) NOT NULL,
  block_start      DATE          NOT NULL,
  block_end        DATE          NOT NULL,
  block_days       INT           NOT NULL,
  inferred_reason  NVARCHAR(32)  NOT NULL,   -- 'vacation_like' | 'sick_like' | ...
  confidence       FLOAT         NOT NULL,   -- 0..1
  dept_support_pct FLOAT         NULL,       -- optional cohort support within department
  is_full_exclude  BIT           NOT NULL,   -- 1=fully exclude days from penalties
  created_at       DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
  PRIMARY KEY (client_id, emp_id, block_start)
);
  CREATE INDEX IX_legit_abs_blocks_client_emp_block_start
    ON dbo.legit_abs_blocks(client_id, emp_id, block_start);


/* seed interventions (dynamic to avoid compile-time name checks) */
DECLARE @sql NVARCHAR(MAX) = N'
  INSERT INTO dbo.interventions(short_text, long_description) VALUES
  (N''1:1 Manager Check-in'', N''Schedule a confidential 30–45 minute conversation to explore concerns, workload, recognition, and career goals. Agree on 2–3 concrete next steps.'' ),
  (N''Career Path Discussion'', N''Present growth options (skills, certifications, rotations). Co-create a 90-day development plan with milestones and sponsorship.'' ),
  (N''Pulse Survey / Stay Interview'', N''Run a short pulse or stay interview to capture drivers of engagement and flight risk.'' ),
  (N''Recognition Boost'', N''Provide specific, timely recognition for recent contributions (public shout-outs, spotlight, points).'' ),
  (N''Compensation Review'', N''Evaluate market parity, comprehensive rewards, and retention levers (bonus, equity refresh, promotion review).'' ),
  (N''Flexible Work Arrangement'', N''Offer remote/hybrid options, flexible hours, or schedule predictability to improve work-life fit.'' ),
  (N''Role/Project Realignment'', N''Align skills to work; re-scope deliverables or rotate projects to reduce friction.'' ),
  (N''Workload Rebalancing'', N''Reassign tasks, shift deadlines, or add temporary help to remove unsustainable peaks.'' ),
  (N''Wellbeing Resources'', N''Offer EAP, mental health days, or wellness resources; coach on boundaries.'' ),
  (N''Coaching & Mentoring'', N''Pair with mentor/coach for growth, feedback, and support.'' ),
  (N''Skills Training'', N''Provide targeted upskilling to match role demands and growth path.'' ),
  (N''Team Capacity Review'', N''Review headcount, bottlenecks, and demand; propose reprioritization or hiring plan.'' ),
  (N''Policy Refresher'', N''Reinforce attendance/ethics policies; clarify expectations and consequences.'' ),
  (N''Compliance Review'', N''Run a discreet compliance review with HR and Security for repeated anomalies.'' ),
  (N''Pattern Escalation'', N''Elevate repeated patterns to HR for documented follow-up.'' ),
  (N''Badge/Access Audit'', N''Audit badge usage, door mismatches, and geo anomalies.'' ),
  (N''Performance Check-in'', N''Clarify goals, expectations, and address blockers; set short review cadence.'' ),
  (N''HRBP Partnership'', N''Engage HR Business Partner to coordinate multi-pronged interventions.'' ),
  (N''Peer Buddy Program'', N''Assign peer support for integration and engagement.'' ),
  (N''Escalation to HRBP'', N''Escalate risk pattern to HRBP for coordinated retention/compliance actions.'' ),
  /* >>> NEW: exact 0-score filler shown by reports */
  (N''No Intervention Needed'', N''Score is low; informational only — monitor within normal cadence.'');
';
EXEC sys.sp_executesql @sql;

  /* seed risk_interventions (dynamic, lookups by short_text) */
  DECLARE @add NVARCHAR(MAX) = N'
    DECLARE @iid INT;
    SELECT @iid = intervention_id FROM dbo.interventions WHERE short_text = @name AND is_active = 1;
    IF @iid IS NOT NULL
      INSERT INTO dbo.risk_interventions(risk_type, min_score, max_score, intervention_id, priority, is_active)
      VALUES (@rtype, @min, @max, @iid, @prio, 1);
  ';
  DECLARE @rtype NVARCHAR(40), @min INT, @max INT, @name NVARCHAR(200), @prio INT;

  /* FLIGHT */
  SET @rtype=N'flight';
  SELECT @min=0,  @max=39, @name=N'1:1 Manager Check-in',   @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=0,  @max=39, @name=N'Wellbeing Resources',     @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=40, @max=59, @name=N'Career Path Discussion',  @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Recognition Boost',       @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Role/Project Realignment',@prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=60, @max=79, @name=N'Career Path Discussion',  @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Compensation Review',     @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Flexible Work Arrangement',@prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Team Capacity Review',    @prio=4; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=80, @max=100, @name=N'Career Path Discussion', @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Compensation Review',    @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Flexible Work Arrangement',@prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Escalation to HRBP',     @prio=4; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  /* WORKLOAD */
  SET @rtype=N'workload';
  SELECT @min=0,  @max=39, @name=N'1:1 Manager Check-in',    @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=0,  @max=39, @name=N'Wellbeing Resources',     @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=40, @max=59, @name=N'Workload Rebalancing',    @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Wellbeing Resources',     @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Team Capacity Review',    @prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=60, @max=79, @name=N'Workload Rebalancing',    @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Performance Check-in',    @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Coaching & Mentoring',    @prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Skills Training',         @prio=4; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=80, @max=100, @name=N'Workload Rebalancing',   @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Performance Check-in',   @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'HRBP Partnership',       @prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Escalation to HRBP',     @prio=4; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  /* INTEGRITY */
  SET @rtype=N'integrity';
  SELECT @min=0,  @max=39, @name=N'1:1 Manager Check-in',    @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=0,  @max=39, @name=N'Policy Refresher',        @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=40, @max=59, @name=N'Policy Refresher',        @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Pattern Escalation',      @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=60, @max=79, @name=N'Policy Refresher',        @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Compliance Review',       @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Badge/Access Audit',      @prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
END
GO

