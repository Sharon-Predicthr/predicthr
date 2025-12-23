-- ============================================================================
-- Flight Risk Model - Default Configuration Values
-- ============================================================================
-- This script inserts default configuration values for the flight risk model
-- into the risk_config table. These values can be overridden per-client.
--
-- Usage:
--   - Run once to set global defaults (client_id = NULL)
--   - Override specific values per-client by inserting with client_id set
-- ============================================================================

PRINT 'Inserting flight risk model default configuration values...';

-- Feature weights (should sum to ~100, will be normalized automatically)
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'flight_risk_w_attendance_decline', N'35.0'),
(NULL, N'flight_risk_w_absence_increase', N'20.0'),
(NULL, N'flight_risk_w_hours_decline', N'15.0'),
(NULL, N'flight_risk_w_arrival_change', N'10.0'),
(NULL, N'flight_risk_w_departure_change', N'10.0'),
(NULL, N'flight_risk_w_non_workday_change', N'5.0'),
(NULL, N'flight_risk_w_multi_factor_bonus', N'5.0');

-- Attendance decline threshold multipliers
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'flight_risk_attendance_threshold_critical', N'0.30'),
(NULL, N'flight_risk_attendance_threshold_high', N'0.20'),
(NULL, N'flight_risk_attendance_threshold_moderate', N'0.10'),
(NULL, N'flight_risk_attendance_mult_critical', N'1.5'),
(NULL, N'flight_risk_attendance_mult_high', N'1.3'),
(NULL, N'flight_risk_attendance_mult_moderate', N'1.1');

-- Absence increase threshold multipliers
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'flight_risk_absence_threshold_critical', N'0.25'),
(NULL, N'flight_risk_absence_threshold_high', N'0.15'),
(NULL, N'flight_risk_absence_mult_critical', N'1.4'),
(NULL, N'flight_risk_absence_mult_high', N'1.2');

-- Multi-factor decline thresholds and bonuses
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'flight_risk_multi_factor_threshold_pct', N'0.05'),
(NULL, N'flight_risk_multi_factor_threshold_arrival_min', N'15'),
(NULL, N'flight_risk_multi_factor_threshold_departure_min', N'15'),
(NULL, N'flight_risk_multi_factor_bonus_4', N'5.0'),
(NULL, N'flight_risk_multi_factor_bonus_3', N'3.0'),
(NULL, N'flight_risk_multi_factor_bonus_2', N'1.0');

-- Risk level boundaries (score ranges)
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'flight_risk_threshold_low', N'25'),      -- 0-25 = Low Risk
(NULL, N'flight_risk_threshold_medium', N'50'),   -- 26-50 = Medium Risk
(NULL, N'flight_risk_threshold_high', N'75');     -- 51-75 = High Risk, 76-100 = Critical Risk

-- Minimum data requirements
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'flight_risk_min_baseline_days', N'14'),
(NULL, N'flight_risk_min_recent_days', N'7');

PRINT 'Flight risk model default configuration values inserted successfully.';
PRINT 'Note: Use ON DUPLICATE KEY or MERGE statements if running multiple times.';
GO

