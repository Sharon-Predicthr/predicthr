# Comparison: usp_calc_flight vs usp_calc_flight_risk

This document explains the key differences between the old and new flight risk calculation procedures.

---

## Overview

| Aspect | Old (`usp_calc_flight`) | New (`usp_calc_flight_risk`) |
|--------|------------------------|------------------------------|
| **Data Source** | `calculated_data` table | `calc_period_metrics` table |
| **Number of Features** | 3 features | 6+ features |
| **Scoring Method** | Simple weighted sum | Weighted sum + multipliers + bonuses |
| **Score Range** | Variable (scaled by days) | 0-100 (capped) |
| **Calculation Approach** | Absolute percentage point drop | Relative percentage change (delta) |

---

## Key Differences

### 1. Data Source Tables

**Old (`usp_calc_flight`):**
- Uses `calculated_data` table
- Metrics: `pres_b_norm`, `pres_r_norm`, `short_gap_count_r`, `max_off_run`
- Uses adjusted metrics if available (`pres_b_norm_adj`, `pres_r_norm_adj`)

**New (`usp_calc_flight_risk`):**
- Uses `calc_period_metrics` table
- Metrics: `presence_pct_r/b`, `absence_pct_r/b`, `avg_minutes_r/b`, `avg_arrival_r/b`, `avg_departure_r/b`, `non_workday_presence_r/b`
- Period-based metrics specifically designed for baseline vs recent comparison

**Impact:** Different underlying data means different calculations and potentially different results.

---

### 2. Features Used

#### Old Procedure Features:

1. **Drop in Presence** (`@drop`)
   - Calculation: `pct_b - pct_r` (absolute percentage point difference)
   - Example: 90% → 70% = 20 percentage point drop
   - Weight: `@w_drop` (default 0.70)

2. **Short Gaps** (`@short`)
   - Calculation: `short_gap_count_r * 5.0`
   - Count of short absence streaks
   - Weight: `@w_short` (default 0.10)

3. **Max Off Streak** (`@streak`)
   - Calculation: `10.0 if max_off_run >= 3, else 0.0`
   - Binary indicator for long absence streaks
   - Weight: `@w_streak` (default 0.20)

**Old Formula:**
```
@raw = (@w_drop * @drop) + (@w_short * @short) + (@w_streak * @streak)
@final = @raw * @scale  (where @scale depends on recent_days)
```

#### New Procedure Features:

1. **Attendance Decline** (35% weight)
   - Calculation: `(presence_pct_b - presence_pct_r) / presence_pct_b` (relative change)
   - Example: 90% → 70% = 22.2% relative decline (not 20 percentage points)
   - With multipliers for severe declines (1.1x, 1.3x, 1.5x)

2. **Absence Increase** (20% weight)
   - Calculation: `(absence_pct_r - absence_pct_b) / absence_pct_b` (relative change)
   - Separate from attendance decline
   - With multipliers for severe increases (1.2x, 1.4x)

3. **Hours Decline** (15% weight)
   - Calculation: `(avg_minutes_b - avg_minutes_r) / avg_minutes_b`
   - Measures reduction in work hours
   - Not in old procedure

4. **Arrival Time Change** (10% weight)
   - Calculation: Minutes later arrival in recent period
   - Measures disengagement through late arrivals
   - Not in old procedure

5. **Departure Time Change** (10% weight)
   - Calculation: Minutes earlier departure in recent period
   - Measures early exits (possibly for interviews)
   - Not in old procedure

6. **Non-Workday Presence Change** (5% weight)
   - Calculation: Change in non-workday presence
   - Measures pattern disruption
   - Not in old procedure

7. **Multi-Factor Decline Bonus** (up to 5 points)
   - Bonus when multiple factors decline simultaneously
   - Not in old procedure

**New Formula:**
```
base_score = (attendance_score × multiplier) + (absence_score × multiplier) + 
             hours_score + arrival_score + departure_score + non_workday_score
final_score = base_score + multi_factor_bonus (capped at 100)
```

---

### 3. Calculation Method Differences

#### Presence/Absence Calculation:

**Old:**
```sql
@pct_b = 100.0 * @pres_b_used / @den_b_used  -- Uses actual presence days count
@pct_r = 100.0 * @pres_r_used / @den_r_used
@drop = @pct_b - @pct_r  -- Absolute difference (percentage points)
```

**New:**
```sql
presence_pct_delta = (presence_pct_b - presence_pct_r) / presence_pct_b  -- Relative change
absence_pct_delta = (absence_pct_r - absence_pct_b) / absence_pct_b     -- Relative change
```

**Example Impact:**
- Old: 90% → 70% = 20 percentage point drop → `@drop = 20`
- New: 90% → 70% = 22.2% relative decline → `presence_pct_delta = 0.222`

**Why Different:** The old method uses absolute percentage point changes, while the new uses relative percentage changes (normalized by baseline). Relative changes are more meaningful when comparing different baseline levels.

---

### 4. Scoring Differences

#### Old Scoring:
- Uses weights as multipliers (0.70, 0.10, 0.20) - not percentages
- Formula: `(@w_drop * @drop) + (@w_short * @short) + (@w_streak * @streak)`
- Has a scaling factor based on `recent_days`: `@scale = CASE WHEN @r >= @scale_min_days THEN 1.0 ELSE @r*1.0/@scale_min_days END`
- Final score: `@raw * @scale` (can vary based on data availability)

**Example Old Calculation:**
```
@drop = 20 (percentage points)
@short = 2 * 5.0 = 10
@streak = 10.0 (if max_off_run >= 3)
@raw = (0.70 * 20) + (0.10 * 10) + (0.20 * 10) = 14 + 1 + 2 = 17
@scale = 0.8 (if recent_days = 8, scale_min_days = 10)
@final = 17 * 0.8 = 13.6 → 14
```

#### New Scoring:
- Uses weights as percentages (35%, 20%, 15%, etc.) that sum to 100
- Each feature score is calculated separately and capped at its weight
- Multipliers applied for severe changes
- Multi-factor bonus added
- Final score capped at 100

**Example New Calculation:**
```
presence_pct_delta = 0.222 (22.2% decline)
attendance_score = 0.222 * 35.0 * 100.0 = 7.77 (capped at 35)
attendance_multiplier = 1.3 (for 20%+ decline)
attendance_final = 7.77 * 1.3 = 10.1

absence_pct_delta = 0.25 (25% increase)
absence_score = 0.25 * 20.0 * 100.0 = 5.0
absence_multiplier = 1.4 (for 25%+ increase)
absence_final = 5.0 * 1.4 = 7.0

... (other features) ...

base_score = 10.1 + 7.0 + ... = 25
multi_factor_bonus = 3 (3 factors declining)
final_score = 25 + 3 = 28 (capped at 100)
```

---

### 5. What Causes Score Differences

The scores will differ because:

1. **Different Metrics:**
   - Old: Only uses presence drop, short gaps, max streak
   - New: Uses 6 different features including hours, arrival/departure times, non-workday presence

2. **Different Calculation Methods:**
   - Old: Absolute percentage point drop (90% → 70% = 20 points)
   - New: Relative percentage change (90% → 70% = 22.2% relative decline)

3. **Different Scoring Approach:**
   - Old: Simple weighted sum with scaling factor
   - New: Weighted sum with multipliers and bonuses, capped at 100

4. **Different Data Sources:**
   - Old: Uses `calculated_data` (may include adjusted metrics)
   - New: Uses `calc_period_metrics` (period-based metrics)

5. **Different Weight Systems:**
   - Old: Multipliers (0.70, 0.10, 0.20) that don't sum to 1 or 100
   - New: Percentage weights (35%, 20%, 15%, etc.) that sum to 100

6. **Presence of Multipliers:**
   - Old: No multipliers for severe changes
   - New: Applies multipliers (1.1x, 1.3x, 1.5x) for severe declines

7. **Multi-Factor Bonus:**
   - Old: No bonus system
   - New: Adds 1-5 bonus points when multiple factors decline

---

### 6. When Scores Will Be Similar

Scores might be similar when:
- Employee has only attendance/absence changes (no time pattern changes)
- Changes are moderate (not triggering multipliers)
- Single factor decline (no multi-factor bonus)
- Similar data in both tables (if `calculated_data` and `calc_period_metrics` align)

---

### 7. When Scores Will Be Very Different

Scores will differ significantly when:
- Employee has time pattern changes (arrival/departure shifts) - not measured in old
- Multiple factors declining simultaneously - triggers bonus in new
- Severe changes (20%+, 30%+) - triggers multipliers in new
- Different underlying data between `calculated_data` and `calc_period_metrics`
- Employee has hours decline but stable attendance - captured in new, not old

---

## Recommendation

**Which procedure to use?**

1. **Use `usp_calc_flight_risk` (new)** if you want:
   - More comprehensive risk assessment (6 features vs 3)
   - Research-backed model with multiple indicators
   - More nuanced scoring with multipliers and bonuses
   - Standardized 0-100 score range
   - Period-based metrics designed for baseline vs recent comparison

2. **Keep `usp_calc_flight` (old)** if you want:
   - Simpler model (3 features)
   - Compatibility with existing reports/dashboards
   - Scoring that scales with data availability
   - Continuity with historical scores

**Migration Path:**
- Run both procedures in parallel for a period
- Compare results and validate which better predicts actual turnover
- Gradually transition to the new procedure once validated
- Update dashboards/reports to use new procedure

---

## Example Comparison

### Employee: John Doe
- Baseline presence: 90%
- Recent presence: 70%
- Short gaps: 2
- Max off streak: 4 days
- Hours decline: 10%
- Arrives 30 minutes later on average
- Leaves 30 minutes earlier on average

**Old Procedure Score:**
```
@drop = 90 - 70 = 20 percentage points
@short = 2 * 5.0 = 10
@streak = 10.0 (max_off_run = 4 >= 3)
@raw = (0.70 * 20) + (0.10 * 10) + (0.20 * 10) = 14 + 1 + 2 = 17
@scale = 1.0 (assuming recent_days >= 10)
@final = 17
```

**New Procedure Score:**
```
attendance_delta = (90 - 70) / 90 = 0.222 (22.2%)
attendance_score = 0.222 * 35.0 * 100.0 = 7.77
attendance_mult = 1.3 (20%+ decline)
attendance_final = 7.77 * 1.3 = 10.1

absence_delta = (30 - 10) / 10 = 2.0 (200% increase, but capped)
absence_score = 20.0 (capped)
absence_mult = 1.4 (critical threshold)
absence_final = 20.0 * 1.4 = 28.0

hours_score = (10% decline) * 15.0 = 1.5
arrival_score = (30 min / 60) * 10.0 = 5.0
departure_score = (30 min / 60) * 10.0 = 5.0
non_workday_score = 0 (assuming no change)

base_score = 10.1 + 28.0 + 1.5 + 5.0 + 5.0 + 0 = 49.6
multi_factor_bonus = 5 (4 factors declining)
final_score = 49.6 + 5 = 54.6 → 55
```

**Result:** Old = 17, New = 55 (very different!)

---

## Summary

The new `usp_calc_flight_risk` procedure is **fundamentally different** from the old `usp_calc_flight` procedure:

- ✅ More comprehensive (6+ features vs 3)
- ✅ Uses relative changes instead of absolute differences
- ✅ Includes multipliers for severe changes
- ✅ Includes multi-factor bonus
- ✅ Standardized 0-100 score range
- ✅ Research-backed feature selection

**Expect scores to differ** - this is expected and intentional. The new procedure is designed to be more sensitive to multiple risk factors and provide a more comprehensive assessment.

