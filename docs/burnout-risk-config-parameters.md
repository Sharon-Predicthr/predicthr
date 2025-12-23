# Burnout Risk Model - Configurable Parameters

This document lists all configurable parameters for the `usp_calc_burnout_risk_score` stored procedure. All parameters are stored in the `risk_config` table and can be set globally (client_id = NULL) or per-client.

---

## Feature Weights

These weights determine how much each feature contributes to the overall risk score. They should ideally sum to 100.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_w_hours_increase` | 40.0 | Weight for work hours increase feature | 0-100 |
| `burnout_risk_w_arrival_earlier` | 15.0 | Weight for earlier arrival pattern | 0-100 |
| `burnout_risk_w_departure_later` | 15.0 | Weight for later departure pattern | 0-100 |
| `burnout_risk_w_non_workday_increase` | 15.0 | Weight for non-workday presence increase | 0-100 |
| `burnout_risk_w_sustained_presence` | 10.0 | Weight for sustained high presence | 0-100 |
| `burnout_risk_w_working_while_sick` | 5.0 | Weight for working while sick pattern | 0-100 |
| `burnout_risk_w_multi_factor_bonus` | 10.0 | Maximum bonus for multi-factor overwork | 0-100 |

**Note:** Weights are automatically normalized if they don't sum to 100.

---

## Hours Increase Thresholds & Multipliers

Controls how hours increase is scored and multiplied based on severity.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_hours_threshold_critical` | 0.30 | Hours increase % to trigger critical multiplier (30% increase) | 0-1 |
| `burnout_risk_hours_threshold_high` | 0.20 | Hours increase % to trigger high multiplier (20% increase) | 0-1 |
| `burnout_risk_hours_threshold_moderate` | 0.10 | Hours increase % to trigger moderate multiplier (10% increase) | 0-1 |
| `burnout_risk_hours_mult_critical` | 1.5 | Multiplier when hours increase > critical threshold | 1.0+ |
| `burnout_risk_hours_mult_high` | 1.3 | Multiplier when hours increase > high threshold | 1.0+ |
| `burnout_risk_hours_mult_moderate` | 1.1 | Multiplier when hours increase > moderate threshold | 1.0+ |

**Example:** If an employee's hours increase by 25%, they trigger the high threshold (20%), so their hours score is multiplied by 1.3x.

---

## Arrival (Earlier) Thresholds & Multipliers

Controls how arriving earlier is scored and multiplied based on severity.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_arrival_threshold_critical` | 90 | Minutes earlier to trigger critical multiplier | 0-300 |
| `burnout_risk_arrival_threshold_high` | 60 | Minutes earlier to trigger high multiplier | 0-300 |
| `burnout_risk_arrival_threshold_moderate` | 30 | Minutes earlier to trigger moderate multiplier | 0-300 |
| `burnout_risk_arrival_mult_critical` | 1.5 | Multiplier when arriving >90 min earlier | 1.0+ |
| `burnout_risk_arrival_mult_high` | 1.3 | Multiplier when arriving >60 min earlier | 1.0+ |
| `burnout_risk_arrival_mult_moderate` | 1.1 | Multiplier when arriving >30 min earlier | 1.0+ |

**Note:** Arrival delta is calculated as `avg_arrival_r - avg_arrival_b`, so negative values indicate arriving earlier.

---

## Departure (Later) Thresholds & Multipliers

Controls how leaving later is scored and multiplied based on severity.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_departure_threshold_critical` | 90 | Minutes later to trigger critical multiplier | 0-300 |
| `burnout_risk_departure_threshold_high` | 60 | Minutes later to trigger high multiplier | 0-300 |
| `burnout_risk_departure_threshold_moderate` | 30 | Minutes later to trigger moderate multiplier | 0-300 |
| `burnout_risk_departure_mult_critical` | 1.5 | Multiplier when leaving >90 min later | 1.0+ |
| `burnout_risk_departure_mult_high` | 1.3 | Multiplier when leaving >60 min later | 1.0+ |
| `burnout_risk_departure_mult_moderate` | 1.1 | Multiplier when leaving >30 min later | 1.0+ |

**Note:** Departure delta is calculated as `avg_departure_r - avg_departure_b`, so positive values indicate leaving later.

---

## Non-Workday Presence Thresholds & Multipliers

Controls how non-workday presence increase is scored and multiplied.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_non_workday_threshold_critical` | 6 | Additional non-workday presence days to trigger critical multiplier | 0-20 |
| `burnout_risk_non_workday_threshold_high` | 4 | Additional non-workday presence days to trigger high multiplier | 0-20 |
| `burnout_risk_non_workday_threshold_moderate` | 2 | Additional non-workday presence days to trigger moderate multiplier | 0-20 |
| `burnout_risk_non_workday_mult_critical` | 1.5 | Multiplier when non-workday increase >= 6 days | 1.0+ |
| `burnout_risk_non_workday_mult_high` | 1.3 | Multiplier when non-workday increase >= 4 days | 1.0+ |
| `burnout_risk_non_workday_mult_moderate` | 1.1 | Multiplier when non-workday increase >= 2 days | 1.0+ |

---

## Sustained Presence Thresholds

Controls how sustained high presence is scored.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_presence_threshold_critical` | 0.98 | Presence % to trigger critical score (98%+) | 0-1 |
| `burnout_risk_presence_threshold_high` | 0.95 | Presence % to trigger high score (95%+) | 0-1 |
| `burnout_risk_presence_threshold_moderate` | 0.90 | Presence % to trigger moderate score (90%+) | 0-1 |

**Note:** Only triggers if presence_pct_r >= presence_pct_b (maintained or increased).

---

## Working While Sick Thresholds

Controls how the "working while sick" pattern is detected and scored.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_working_sick_absence_threshold_high` | 0.20 | Absence % decrease to trigger high score (20% decrease) | 0-1 |
| `burnout_risk_working_sick_absence_threshold_moderate` | 0.10 | Absence % decrease to trigger moderate score (10% decrease) | 0-1 |
| `burnout_risk_working_sick_hours_threshold_high` | 0.10 | Hours % increase to trigger high score (10% increase) | 0-1 |
| `burnout_risk_working_sick_hours_threshold_moderate` | 0.05 | Hours % increase to trigger moderate score (5% increase) | 0-1 |

**Note:** Both conditions must be met (absence decrease AND hours increase).

---

## Multi-Factor Overwork Thresholds & Bonuses

Controls how multiple overwork indicators are combined for bonus points.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_multi_factor_threshold_hours_pct` | 0.10 | Hours increase % to count as factor (10%) | 0-1 |
| `burnout_risk_multi_factor_threshold_arrival_min` | 30 | Minutes earlier to count as factor | 0-300 |
| `burnout_risk_multi_factor_threshold_departure_min` | 30 | Minutes later to count as factor | 0-300 |
| `burnout_risk_multi_factor_threshold_non_workday` | 1 | Non-workday increase to count as factor | 0-20 |
| `burnout_risk_multi_factor_bonus_4` | 10.0 | Bonus points when 4+ factors present | 0-20 |
| `burnout_risk_multi_factor_bonus_3` | 6.0 | Bonus points when 3 factors present | 0-20 |
| `burnout_risk_multi_factor_bonus_2` | 3.0 | Bonus points when 2 factors present | 0-20 |

**Overwork factors counted:**
1. Hours increase > threshold
2. Arriving earlier > threshold
3. Leaving later > threshold
4. Non-workday increase > threshold
5. Sustained high presence (>= 90% and >= baseline)

---

## Risk Level Boundaries

Controls the score ranges for different risk levels.

| Config Key | Default | Description | Score Range |
|------------|---------|-------------|-------------|
| `burnout_risk_threshold_low` | 30 | Score below this = Low Risk | 0-100 |
| `burnout_risk_threshold_medium` | 50 | Score >= low and < medium = Medium Risk | 0-100 |
| `burnout_risk_threshold_high` | 70 | Score >= medium and < high = High Risk | 0-100 |

**Risk Levels:**
- **Low Risk**: 0-29 points
- **Medium Risk**: 30-49 points
- **High Risk**: 50-69 points
- **Critical Risk**: 70-100 points

---

## Minimum Data Requirements

Controls minimum data required to calculate risk scores.

| Config Key | Default | Description | Range |
|------------|---------|-------------|-------|
| `burnout_risk_min_baseline_days` | 14 | Minimum workdays in baseline period | 1-365 |
| `burnout_risk_min_recent_days` | 7 | Minimum workdays in recent period | 1-365 |

**Note:** Employees with insufficient data are excluded from calculations.

---

## Usage Examples

### Set Global Defaults
```sql
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(NULL, N'burnout_risk_w_hours_increase', N'45.0'),
(NULL, N'burnout_risk_threshold_high', N'75.0');
```

### Override for Specific Client
```sql
INSERT INTO dbo.risk_config (client_id, config_key, config_value) VALUES
(N'CLIENT123', N'burnout_risk_w_hours_increase', N'50.0'),
(N'CLIENT123', N'burnout_risk_threshold_high', N'80.0');
```

### Update Existing Configuration
```sql
UPDATE dbo.risk_config
SET config_value = N'0.25'
WHERE client_id = N'CLIENT123' 
  AND config_key = N'burnout_risk_hours_threshold_high';
```

---

## Loading Default Configuration

To load all default values, run:
```sql
:r /db/seed-data/burnout_risk_default_config.sql
```

Or manually execute the SQL script from `database/seed-data/burnout_risk_default_config.sql`.

---

## Notes

- All numeric values should be stored as strings in the `config_value` column
- Client-specific values override global values (client_id = NULL)
- Weights are automatically normalized if they don't sum to 100
- Final risk scores are capped at 100 points
- All thresholds use inclusive comparisons (>= for boundaries)

