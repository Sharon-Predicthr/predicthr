# Flight Risk Model - Configuration Parameters

This document lists all configurable parameters for the `usp_calc_flight_risk` stored procedure that should be stored in the `risk_config` table.

## Configuration Table

All parameters are stored in `dbo.risk_config` with the following structure:
- `client_id`: NULL for global defaults, or specific client_id for client-specific overrides
- `config_key`: The parameter name (as listed below)
- `config_value`: The parameter value as a string

## Feature Weights

These control how much each feature contributes to the risk score. Default weights sum to 100.

| Config Key | Default Value | Description |
|------------|---------------|-------------|
| `flight_risk_w_attendance_decline` | `35.0` | Weight for attendance decline (0-100 points) |
| `flight_risk_w_absence_increase` | `20.0` | Weight for absence increase (0-100 points) |
| `flight_risk_w_hours_decline` | `15.0` | Weight for hours decline (0-100 points) |
| `flight_risk_w_arrival_change` | `10.0` | Weight for arrival time change (0-100 points) |
| `flight_risk_w_departure_change` | `10.0` | Weight for departure time change (0-100 points) |
| `flight_risk_w_non_workday_change` | `5.0` | Weight for non-workday presence change (0-100 points) |
| `flight_risk_w_multi_factor_bonus` | `5.0` | Maximum bonus points for multi-factor decline (0-100 points) |

**Note**: If weights don't sum to 100, they will be automatically normalized.

## Attendance Threshold Multipliers

These apply multipliers when attendance decline exceeds certain thresholds.

| Config Key | Default Value | Description |
|------------|---------------|-------------|
| `flight_risk_attendance_threshold_critical` | `0.30` | Critical threshold (30% decline = 1.5x multiplier) |
| `flight_risk_attendance_threshold_high` | `0.20` | High threshold (20% decline = 1.3x multiplier) |
| `flight_risk_attendance_threshold_moderate` | `0.10` | Moderate threshold (10% decline = 1.1x multiplier) |
| `flight_risk_attendance_mult_critical` | `1.5` | Multiplier for critical attendance decline |
| `flight_risk_attendance_mult_high` | `1.3` | Multiplier for high attendance decline |
| `flight_risk_attendance_mult_moderate` | `1.1` | Multiplier for moderate attendance decline |

## Absence Threshold Multipliers

These apply multipliers when absence increase exceeds certain thresholds.

| Config Key | Default Value | Description |
|------------|---------------|-------------|
| `flight_risk_absence_threshold_critical` | `0.25` | Critical threshold (25% increase = 1.4x multiplier) |
| `flight_risk_absence_threshold_high` | `0.15` | High threshold (15% increase = 1.2x multiplier) |
| `flight_risk_absence_mult_critical` | `1.4` | Multiplier for critical absence increase |
| `flight_risk_absence_mult_high` | `1.2` | Multiplier for high absence increase |

## Multi-Factor Decline Thresholds

These determine when multiple factors are considered "declining" for bonus calculation.

| Config Key | Default Value | Description |
|------------|---------------|-------------|
| `flight_risk_multi_factor_threshold_pct` | `0.05` | Percentage change threshold (5%) for presence/hours decline |
| `flight_risk_multi_factor_threshold_arrival_min` | `15` | Minutes threshold for arrival time change (15 min later) |
| `flight_risk_multi_factor_threshold_departure_min` | `15` | Minutes threshold for departure time change (15 min earlier) |
| `flight_risk_multi_factor_bonus_4` | `5.0` | Bonus points when 4 factors are declining |
| `flight_risk_multi_factor_bonus_3` | `3.0` | Bonus points when 3 factors are declining |
| `flight_risk_multi_factor_bonus_2` | `1.0` | Bonus points when 2 factors are declining |

## Risk Level Boundaries

These define the score ranges for different risk levels.

| Config Key | Default Value | Description |
|------------|---------------|-------------|
| `flight_risk_threshold_low` | `25` | Score boundary between Low and Medium risk (0-25 = Low) |
| `flight_risk_threshold_medium` | `50` | Score boundary between Medium and High risk (26-50 = Medium) |
| `flight_risk_threshold_high` | `75` | Score boundary between High and Critical risk (51-75 = High, 76-100 = Critical) |

## Minimum Data Requirements

These ensure sufficient data is available before calculating risk scores.

| Config Key | Default Value | Description |
|------------|---------------|-------------|
| `flight_risk_min_baseline_days` | `14` | Minimum baseline period workdays required |
| `flight_risk_min_recent_days` | `7` | Minimum recent period workdays required |

---

## Example: Inserting Default Configuration Values

To set global defaults for all clients:

```sql
-- Feature weights
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, 'flight_risk_w_attendance_decline', '35.0'),
(NULL, 'flight_risk_w_absence_increase', '20.0'),
(NULL, 'flight_risk_w_hours_decline', '15.0'),
(NULL, 'flight_risk_w_arrival_change', '10.0'),
(NULL, 'flight_risk_w_departure_change', '10.0'),
(NULL, 'flight_risk_w_non_workday_change', '5.0'),
(NULL, 'flight_risk_w_multi_factor_bonus', '5.0');

-- Attendance thresholds
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, 'flight_risk_attendance_threshold_critical', '0.30'),
(NULL, 'flight_risk_attendance_threshold_high', '0.20'),
(NULL, 'flight_risk_attendance_threshold_moderate', '0.10'),
(NULL, 'flight_risk_attendance_mult_critical', '1.5'),
(NULL, 'flight_risk_attendance_mult_high', '1.3'),
(NULL, 'flight_risk_attendance_mult_moderate', '1.1');

-- Absence thresholds
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, 'flight_risk_absence_threshold_critical', '0.25'),
(NULL, 'flight_risk_absence_threshold_high', '0.15'),
(NULL, 'flight_risk_absence_mult_critical', '1.4'),
(NULL, 'flight_risk_absence_mult_high', '1.2');

-- Multi-factor thresholds
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, 'flight_risk_multi_factor_threshold_pct', '0.05'),
(NULL, 'flight_risk_multi_factor_threshold_arrival_min', '15'),
(NULL, 'flight_risk_multi_factor_threshold_departure_min', '15'),
(NULL, 'flight_risk_multi_factor_bonus_4', '5.0'),
(NULL, 'flight_risk_multi_factor_bonus_3', '3.0'),
(NULL, 'flight_risk_multi_factor_bonus_2', '1.0');

-- Risk level boundaries
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, 'flight_risk_threshold_low', '25'),
(NULL, 'flight_risk_threshold_medium', '50'),
(NULL, 'flight_risk_threshold_high', '75');

-- Minimum data requirements
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, 'flight_risk_min_baseline_days', '14'),
(NULL, 'flight_risk_min_recent_days', '7');
```

## Example: Overriding for Specific Client

To override a specific parameter for a client:

```sql
-- Example: Client 'ABC123' wants higher weight on attendance decline
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
('ABC123', 'flight_risk_w_attendance_decline', '40.0');

-- Example: Client 'XYZ789' wants different risk thresholds
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
('XYZ789', 'flight_risk_threshold_low', '20'),
('XYZ789', 'flight_risk_threshold_medium', '45'),
('XYZ789', 'flight_risk_threshold_high', '70');
```

## Configuration Precedence

The stored procedure uses the following precedence order:
1. **Client-specific configuration** (`client_id = 'ABC123'`) - Highest priority
2. **Global configuration** (`client_id IS NULL`) - Default fallback
3. **Hard-coded default** - Last resort if not in config table

This allows clients to override specific parameters while inheriting defaults for others.

## Tuning Recommendations

### Adjusting Sensitivity

**More Sensitive (catch more at-risk employees, but more false positives):**
- Lower `flight_risk_threshold_low` (e.g., 15 instead of 25)
- Lower `flight_risk_attendance_threshold_moderate` (e.g., 0.05 instead of 0.10)
- Lower `flight_risk_multi_factor_threshold_pct` (e.g., 0.03 instead of 0.05)

**Less Sensitive (fewer false positives, but might miss some at-risk employees):**
- Raise `flight_risk_threshold_low` (e.g., 30 instead of 25)
- Raise `flight_risk_attendance_threshold_moderate` (e.g., 0.15 instead of 0.10)
- Raise `flight_risk_multi_factor_threshold_pct` (e.g., 0.08 instead of 0.05)

### Adjusting Feature Importance

**Emphasize Attendance Patterns:**
- Increase `flight_risk_w_attendance_decline` (e.g., 40.0)
- Decrease other weights proportionally

**Emphasize Absence Patterns:**
- Increase `flight_risk_w_absence_increase` (e.g., 25.0)
- Decrease other weights proportionally

**De-emphasize Time Patterns:**
- Decrease `flight_risk_w_arrival_change` and `flight_risk_w_departure_change` (e.g., 5.0 each)

---

## Complete Configuration Script

See `database/seed-data/flight_risk_default_config.sql` for a complete script with all default values.

