PRINT 'SEED STARTED';
GO

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

GO
