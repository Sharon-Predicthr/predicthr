-- Script to insert default configuration values into the dbo.risk_config table.
-- All values are inserted with a NULL client_id, indicating they are global/default settings.

INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
    -- Calendar & Session Settings
    (NULL, 'calendar_work_threshold_pct', '30'),   -- Minimum percentage of the workday that must be scheduled in the calendar
    (NULL, 'short_session_minutes',       '180'),  -- Duration (in minutes) defining a "short" work session (3 hours)
    (NULL, 'odd_min_minutes',             '10'),   -- Minimum duration for an "odd" or short, potentially suspicious session
    (NULL, 'odd_max_minutes',             '60'),   -- Maximum duration for an "odd" session
    (NULL, 'long_day_minutes',            '600'),  -- Duration (in minutes) defining a "long" workday (10 hours)
    (NULL, 'late_start_hhmm',             '10:00'),-- Time defining a "late" start of the workday

    -- Flight Risk Category Weights & Thresholds
    (NULL, 'flight_w_drop',               '0.70'), -- Weight for the "drop" factor in flight risk calculation
    (NULL, 'flight_w_short',              '0.10'), -- Weight for the "short session" factor in flight risk
    (NULL, 'flight_w_streak',             '0.20'), -- Weight for the "streak" factor in flight risk
    (NULL, 'flight_scale_min_recent_days','10'),   -- Minimum number of recent days required to calculate the flight score scale
    (NULL, 'flight_intervention_min_score','15'),  -- Minimum score to trigger a flight risk intervention

    -- Integrity Risk Category Weights
    (NULL, 'integrity_w_odd',             '0.50'), -- Weight for the "odd session" factor in integrity risk
    (NULL, 'integrity_w_door',            '0.30'), -- Weight for the "door/physical access" factor
    (NULL, 'integrity_w_ping',            '0.20'), -- Weight for the "ping/activity" factor
	(NULL, 'integrity_intervention_min_score','15'), -- Minimum score to trigger an integrity risk intervention

    -- Workload Risk Category Weights & Thresholds
    (NULL, 'workload_w_long',             '0.60'), -- Weight for the "long day" factor in workload risk
    (NULL, 'workload_w_late',             '0.40'), -- Weight for the "late start" factor in workload risk
    (NULL, 'workload_bonus_points',       '5'),    -- Bonus points awarded for high-performing metrics
    (NULL, 'workload_bonus_delta_pct',    '10'),   -- Percentage delta threshold for bonus points
	(NULL, 'workload_intervention_min_score','15'), -- Minimum score to trigger a workload risk intervention

    -- Baseline and Recent Window Settings
	(NULL, N'window_baseline_pct',         '70'),   -- Percentage of time window used for the baseline period
	(NULL, N'recent_min_days',             '20'),   -- Minimum days in the "recent" comparison window
	(NULL, N'recent_max_days',             '45'),   -- Maximum days in the "recent" comparison window
	(NULL, N'holiday_coverage_threshold_pct','15'), -- Threshold for required coverage during a holiday period
	(NULL, N'dept_holiday_threshold_pct',  '25'),   -- Threshold for department-wide holiday time
	(NULL, N'pto_min_block_days',          '5'),    -- Minimum number of days for a PTO block
	(NULL, N'sick_max_block_days',         '3'),    -- Maximum number of days for a sick leave block
	(NULL, N'legit_conf_full_exclude_min', '0.6'),  -- Minimum percentage for a legitimate conflict to fully exclude
	(NULL, N'legit_conf_partial_min',      '0.3'),  -- Minimum percentage for a legitimate conflict to partially exclude

	(NULL, N'baseline_min_days',           '15');   -- Minimum number of days required for the baseline period
GO
