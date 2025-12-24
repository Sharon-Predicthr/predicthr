# Fraud Risk Model - Configurable Parameters

This document lists all configurable parameters for the `usp_calc_fraud_risk_score` stored procedure. All parameters are stored in the `risk_config` table and can be set globally (client_id = NULL) or per-client.

---

## Feature Weights

These weights determine how much each feature contributes to the overall fraud risk score. They should ideally sum to 100.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `fraud_risk_w_door_mismatch` | 35.0 | Weight for door mismatch feature (buddy punching indicator) | 0-100 |
| `fraud_risk_w_pingpong` | 25.0 | Weight for ping-pong patterns (excessive entries/exits) | 0-100 |
| `fraud_risk_w_odd_hours` | 15.0 | Weight for odd/remote hours patterns | 0-100 |
| `fraud_risk_w_session_length` | 10.0 | Weight for unusual session lengths | 0-100 |
| `fraud_risk_w_sessions_per_day` | 10.0 | Weight for excessive daily sessions | 0-100 |
| `fraud_risk_w_multi_factor_bonus` | 5.0 | Maximum bonus for multi-factor fraud indicators | 0-20 |

**Note:** Weights are automatically normalized if they don't sum to 100.

---

## Minimum Data Requirements

Controls minimum data required for reliable fraud risk calculations.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `fraud_risk_min_peer_group_size` | 5 | Minimum employees in peer group for statistical validity | 3-50 |
| `fraud_risk_min_days_analyzed` | 5 | Minimum days of data per employee for analysis | 1-90 |

**Peer Group Selection Logic:**
1. **Primary**: Department + Role (if >= min_peer_group_size)
2. **Fallback**: Department only (if >= min_peer_group_size)
3. **Last Resort**: Client-wide (if department groups too small)

---

## Multi-Factor Fraud Thresholds & Bonuses

Controls how multiple fraud indicators are combined for bonus points.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `fraud_risk_multi_factor_threshold_percentile` | 90.0 | Percentile threshold for counting as "factor" (90th percentile) | 0-100 |
| `fraud_risk_multi_factor_bonus_3` | 5.0 | Bonus points when 3+ factors exceed threshold | 0-20 |
| `fraud_risk_multi_factor_bonus_2` | 3.0 | Bonus points when 2 factors exceed threshold | 0-20 |

**Multi-Factor Counting:**
Factors counted when employee is at or above threshold percentile for:
- Door mismatch
- Ping-pong patterns
- Odd/remote hours

**Example:** If 3 factors are in the 90th+ percentile, add 5 bonus points.

---

## Risk Level Boundaries

Controls the score ranges for different risk levels.

| Config Key | Default | Description | Score Range |
|------------|---------|-------------|-------------|
| `fraud_risk_threshold_low` | 40 | Score below this = Low Risk | 0-100 |
| `fraud_risk_threshold_medium` | 60 | Score >= low and < medium = Medium Risk | 0-100 |
| `fraud_risk_threshold_high` | 80 | Score >= medium and < high = High Risk | 0-100 |

**Risk Levels:**
- **Low Risk**: 0-39 points - Within normal range or slight deviations
- **Medium Risk**: 40-59 points - Moderate statistical outliers (1-2 std devs)
- **High Risk**: 60-79 points - Significant statistical outliers (2-3 std devs)
- **Critical Risk**: 80-100 points - Extreme statistical outliers (3+ std devs)

---

## Statistical Calculation Details

### Z-Score Calculation
```
Z-score = (employee_value - peer_group_mean) / peer_group_std_dev
```

### Percentile Conversion
```
Percentile = 50 + (z_score * 20)  -- Capped at 0-100
```
- Z-score of 0 = 50th percentile (average)
- Z-score of +2.5 = 100th percentile (extreme outlier)
- Only positive Z-scores contribute to fraud risk (above average is suspicious)

**Note:** For session length, negative Z-scores (very short sessions) are also considered suspicious and converted to high percentiles.

---

## Usage Examples

### Set Global Defaults
```sql
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'fraud_risk_w_door_mismatch', N'40.0'),
(NULL, N'fraud_risk_threshold_high', N'75.0');
```

### Override for Specific Client
```sql
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(N'CLIENT123', N'fraud_risk_w_door_mismatch', N'45.0'),
(N'CLIENT123', N'fraud_risk_min_peer_group_size', N'10');
```

### Update Existing Configuration
```sql
UPDATE dbo.risk_config
SET config_value = N'50.0'
WHERE client_id = N'CLIENT123' 
  AND config_key = N'fraud_risk_threshold_high';
```

---

## Loading Default Configuration

To load all default values, run:
```sql
:r /db/seed-data/fraud_risk_default_config.sql
```

Or manually execute the SQL script from `database/seed-data/fraud_risk_default_config.sql`.

---

## Notes

- All numeric values should be stored as strings in the `config_value` column
- Client-specific values override global values (client_id = NULL)
- Weights are automatically normalized if they don't sum to 100
- Final fraud risk scores are capped at 100 points
- Z-scores are calculated using peer group statistics (department+role, department-only, or client-wide)
- Only positive Z-scores contribute to fraud risk (employees above peer average)
- Statistical methods ensure fraud detection is based on population anomalies, not personal baselines

