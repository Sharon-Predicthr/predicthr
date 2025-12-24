-- ============================================================================
-- Fraud Risk Model - Default Configuration Values
-- ============================================================================
-- This script inserts default configuration values for the fraud risk model
-- into the risk_config table. These values can be overridden per-client.
--
-- Usage:
--   - Run once to set global defaults (client_id = NULL)
--   - Override specific values per-client by inserting with client_id set
-- ============================================================================

PRINT 'Inserting fraud risk model default configuration values...';

-- Feature weights (should sum to 100, will be normalized automatically)
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'fraud_risk_w_door_mismatch', N'35.0'),
(NULL, N'fraud_risk_w_pingpong', N'25.0'),
(NULL, N'fraud_risk_w_odd_hours', N'15.0'),
(NULL, N'fraud_risk_w_session_length', N'10.0'),
(NULL, N'fraud_risk_w_sessions_per_day', N'10.0'),
(NULL, N'fraud_risk_w_multi_factor_bonus', N'5.0');

-- Minimum data requirements
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'fraud_risk_min_peer_group_size', N'5'),  -- Minimum employees in peer group
(NULL, N'fraud_risk_min_days_analyzed', N'5');     -- Minimum days of data per employee

-- Multi-factor fraud thresholds and bonuses
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'fraud_risk_multi_factor_threshold_percentile', N'90.0'),  -- 90th percentile threshold
(NULL, N'fraud_risk_multi_factor_bonus_3', N'5.0'),                 -- 3+ factors at threshold
(NULL, N'fraud_risk_multi_factor_bonus_2', N'3.0');                 -- 2 factors at threshold

-- Risk level boundaries (score ranges)
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'fraud_risk_threshold_low', N'40'),      -- 0-40 = Low Risk
(NULL, N'fraud_risk_threshold_medium', N'60'),   -- 41-60 = Medium Risk
(NULL, N'fraud_risk_threshold_high', N'80');     -- 61-80 = High Risk, 81-100 = Critical Risk

PRINT 'Fraud risk model default configuration values inserted successfully.';
PRINT 'Note: Use ON DUPLICATE KEY or MERGE statements if running multiple times.';
GO

