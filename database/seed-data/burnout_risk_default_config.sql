-- ============================================================================
-- Burnout Risk Model - Default Configuration Values
-- ============================================================================
-- This script inserts default configuration values for the burnout risk model
-- into the risk_config table. These values can be overridden per-client.
--
-- Usage:
--   - Run once to set global defaults (client_id = NULL)
--   - Override specific values per-client by inserting with client_id set
-- ============================================================================

PRINT 'Inserting burnout risk model default configuration values...';

-- Feature weights (should sum to 100, will be normalized automatically)
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_w_hours_increase', N'40.0'),
(NULL, N'burnout_risk_w_arrival_earlier', N'15.0'),
(NULL, N'burnout_risk_w_departure_later', N'15.0'),
(NULL, N'burnout_risk_w_non_workday_increase', N'15.0'),
(NULL, N'burnout_risk_w_sustained_presence', N'10.0'),
(NULL, N'burnout_risk_w_working_while_sick', N'5.0'),
(NULL, N'burnout_risk_w_multi_factor_bonus', N'10.0');

-- Hours increase threshold multipliers
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_hours_threshold_critical', N'0.30'),  -- 30% increase
(NULL, N'burnout_risk_hours_threshold_high', N'0.20'),      -- 20% increase
(NULL, N'burnout_risk_hours_threshold_moderate', N'0.10'),  -- 10% increase
(NULL, N'burnout_risk_hours_mult_critical', N'1.5'),
(NULL, N'burnout_risk_hours_mult_high', N'1.3'),
(NULL, N'burnout_risk_hours_mult_moderate', N'1.1');

-- Arrival (earlier) threshold multipliers
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_arrival_threshold_critical', N'90'),  -- 90 minutes earlier
(NULL, N'burnout_risk_arrival_threshold_high', N'60'),      -- 60 minutes earlier
(NULL, N'burnout_risk_arrival_threshold_moderate', N'30'),  -- 30 minutes earlier
(NULL, N'burnout_risk_arrival_mult_critical', N'1.5'),
(NULL, N'burnout_risk_arrival_mult_high', N'1.3'),
(NULL, N'burnout_risk_arrival_mult_moderate', N'1.1');

-- Departure (later) threshold multipliers
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_departure_threshold_critical', N'90'),  -- 90 minutes later
(NULL, N'burnout_risk_departure_threshold_high', N'60'),      -- 60 minutes later
(NULL, N'burnout_risk_departure_threshold_moderate', N'30'),  -- 30 minutes later
(NULL, N'burnout_risk_departure_mult_critical', N'1.5'),
(NULL, N'burnout_risk_departure_mult_high', N'1.3'),
(NULL, N'burnout_risk_departure_mult_moderate', N'1.1');

-- Non-workday presence threshold multipliers
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_non_workday_threshold_critical', N'6'),  -- 6+ days
(NULL, N'burnout_risk_non_workday_threshold_high', N'4'),      -- 4+ days
(NULL, N'burnout_risk_non_workday_threshold_moderate', N'2'),  -- 2+ days
(NULL, N'burnout_risk_non_workday_mult_critical', N'1.5'),
(NULL, N'burnout_risk_non_workday_mult_high', N'1.3'),
(NULL, N'burnout_risk_non_workday_mult_moderate', N'1.1');

-- Sustained presence thresholds
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_presence_threshold_critical', N'0.98'),  -- 98%+
(NULL, N'burnout_risk_presence_threshold_high', N'0.95'),      -- 95%+
(NULL, N'burnout_risk_presence_threshold_moderate', N'0.90');  -- 90%+

-- Working while sick thresholds
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_working_sick_absence_threshold_high', N'0.20'),      -- 20% decrease in absence
(NULL, N'burnout_risk_working_sick_absence_threshold_moderate', N'0.10'),  -- 10% decrease in absence
(NULL, N'burnout_risk_working_sick_hours_threshold_high', N'0.10'),        -- 10% increase in hours
(NULL, N'burnout_risk_working_sick_hours_threshold_moderate', N'0.05');    -- 5% increase in hours

-- Multi-factor overwork thresholds and bonuses
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_multi_factor_threshold_hours_pct', N'0.10'),  -- 10% hours increase
(NULL, N'burnout_risk_multi_factor_threshold_arrival_min', N'30'),  -- 30 minutes earlier
(NULL, N'burnout_risk_multi_factor_threshold_departure_min', N'30'), -- 30 minutes later
(NULL, N'burnout_risk_multi_factor_threshold_non_workday', N'1'),   -- 1+ non-workday
(NULL, N'burnout_risk_multi_factor_bonus_4', N'10.0'),              -- 4+ factors
(NULL, N'burnout_risk_multi_factor_bonus_3', N'6.0'),               -- 3 factors
(NULL, N'burnout_risk_multi_factor_bonus_2', N'3.0');               -- 2 factors

-- Risk level boundaries (score ranges)
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_threshold_low', N'30'),      -- 0-30 = Low Risk
(NULL, N'burnout_risk_threshold_medium', N'50'),   -- 31-50 = Medium Risk
(NULL, N'burnout_risk_threshold_high', N'70');     -- 51-70 = High Risk, 71-100 = Critical Risk

-- Minimum data requirements
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_min_baseline_days', N'14'),
(NULL, N'burnout_risk_min_recent_days', N'7');

PRINT 'Burnout risk model default configuration values inserted successfully.';
PRINT 'Note: Use ON DUPLICATE KEY or MERGE statements if running multiple times.';
GO

