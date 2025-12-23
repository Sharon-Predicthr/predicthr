# Burnout/Overwork Risk Model Design

## Executive Summary

This document outlines a burnout/overwork risk scoring model based on behavioral patterns in work hours, presence, and time patterns from the `calc_period_metrics` table. The model identifies employees most likely to be experiencing burnout by detecting patterns consistent with overwork, excessive hours, and unsustainable work patterns.

**Note:** This model is distinct from the Flight Risk model - burnout indicates **overwork/overcommitment**, while flight risk indicates **disengagement/withdrawal**.

---

## A. Feature Selection (Based on Research)

### Research-Backed Indicators:

Burnout is characterized by three dimensions (Maslach Burnout Inventory):
1. **Emotional Exhaustion** - Feeling drained and depleted
2. **Depersonalization** - Cynicism and detachment from work
3. **Reduced Personal Accomplishment** - Reduced sense of competence

Behavioral indicators from workplace metrics:

### 1. **Excessive Work Hours Increase** (Strongest Predictor)
   - **Research**: Studies consistently show working 50+ hours/week increases burnout risk by 50-70% (Harvard Business Review, Gallup)
   - **Feature**: `avg_minutes_r` vs `avg_minutes_b` (INCREASE)
   - **Calculation**: `(avg_minutes_r - avg_minutes_b) / avg_minutes_b` (percentage increase)
   - **Rationale**: Sustained increases in daily work hours are the primary burnout driver
   - **Thresholds**: 
     - >10% increase = moderate risk
     - >20% increase = high risk
     - >30% increase = critical risk

### 2. **Earlier Arrival Times** (Arriving Early Pattern)
   - **Research**: Arriving significantly earlier indicates overcommitment and inability to disconnect (Journal of Occupational Health Psychology)
   - **Feature**: `avg_arrival_r` vs `avg_arrival_b` (EARLIER arrival = negative delta in minutes)
   - **Calculation**: Convert time difference to minutes, negative = earlier arrival
   - **Rationale**: Starting work earlier = working longer days = burnout risk
   - **Thresholds**:
     - Arriving 30+ minutes earlier = moderate risk
     - Arriving 60+ minutes earlier = high risk
     - Arriving 90+ minutes earlier = critical risk

### 3. **Later Departure Times** (Staying Late Pattern)
   - **Research**: Staying late regularly correlates with emotional exhaustion (Work & Stress Journal)
   - **Feature**: `avg_departure_r` vs `avg_departure_b` (LATER departure = positive delta in minutes)
   - **Calculation**: Convert time difference to minutes, positive = later departure
   - **Rationale**: Leaving later = working longer days = burnout risk
   - **Thresholds**:
     - Leaving 30+ minutes later = moderate risk
     - Leaving 60+ minutes later = high risk
     - Leaving 90+ minutes later = critical risk

### 4. **Increased Non-Workday Presence** (Working Weekends/Holidays)
   - **Research**: Working non-standard days is associated with higher burnout rates (European Journal of Work Psychology)
   - **Feature**: `non_workday_presence_r` vs `non_workday_presence_b` (INCREASE)
   - **Calculation**: `(non_workday_presence_r - non_workday_presence_b)` (absolute increase in days)
   - **Rationale**: Working weekends/holidays indicates inability to disconnect
   - **Thresholds**:
     - 2+ additional non-workday presence days = moderate risk
     - 4+ additional days = high risk
     - 6+ additional days = critical risk

### 5. **Sustained High Presence Rate** (No Recovery Time)
   - **Research**: High attendance without breaks leads to exhaustion (Mayo Clinic Proceedings)
   - **Feature**: `presence_pct_r` when already high (>90%) AND no decline from baseline
   - **Calculation**: `presence_pct_r` with bonus if >90% AND `presence_pct_r >= presence_pct_b`
   - **Rationale**: Perfect attendance over extended periods indicates lack of recovery time
   - **Thresholds**:
     - >90% presence with no decline = moderate risk
     - >95% presence with no decline = high risk
     - >98% presence = critical risk

### 6. **Absence Decline While Hours Increase** (Working While Sick)
   - **Research**: Reduced absence while hours increase suggests working through illness (Journal of Applied Psychology)
   - **Feature**: Combined indicator: `absence_pct_r < absence_pct_b` AND `avg_minutes_r > avg_minutes_b`
   - **Calculation**: Binary indicator when both conditions met
   - **Rationale**: Pattern suggests working through illness/exhaustion = burnout indicator
   - **Thresholds**:
     - Both conditions met = moderate risk indicator
     - Strong decline in absence + strong increase in hours = high risk

### 7. **Extended Work Periods** (Long Stretch Without Breaks)
   - **Research**: Consecutive high-attendance periods increase burnout risk
   - **Feature**: Derived from `workdays_r` combined with high `presence_pct_r`
   - **Calculation**: `workdays_r` (if >= 60 workdays with >90% presence)
   - **Rationale**: Extended periods without recovery increase burnout risk
   - **Note**: This is more of a contextual factor than a primary feature

### Features NOT Used (Why):

- `absence_pct_r` / `absence_pct_b` alone: Too ambiguous (could mean healthy or burned out)
- `presence_pct_r` / `presence_pct_b` alone: High presence is good unless combined with excessive hours
- Raw counts (`presence_r`, `absence_r`): Less meaningful than percentages or deltas
- Date fields: Used for windowing, not as features

---

## B. Feature Weights

### Recommended Weights (Total = 100 points):

| Feature | Weight | Rationale |
|---------|--------|-----------|
| **1. Work Hours Increase** (`avg_minutes_delta_pct`) | **40%** | Strongest predictor - excessive hours are #1 burnout driver |
| **2. Earlier Arrival** (`arrival_delta_minutes`, negative) | **15%** | Strong predictor - early starts indicate overcommitment |
| **3. Later Departure** (`departure_delta_minutes`, positive) | **15%** | Strong predictor - late departures indicate extended days |
| **4. Non-Workday Presence Increase** (`non_workday_delta`) | **15%** | Moderate predictor - weekend work indicates inability to disconnect |
| **5. High Sustained Presence** (`presence_pct_r` when high + stable) | **10%** | Moderate predictor - no recovery time |
| **6. Working While Sick Pattern** (absence decline + hours increase) | **5%** | Weak predictor - indicator of pushing through exhaustion |
| **7. Multi-Factor Overwork Bonus** | **Up to +10 bonus** | Amplifier when 3+ factors indicate overwork simultaneously |

**Total Base: 100 points, with up to +10 bonus for multi-factor overwork patterns**

### Weight Rationale:

1. **Work Hours (40%)**: Research consistently identifies excessive hours as the primary burnout driver. This gets the highest weight.

2. **Time Pattern Changes (15% + 15% = 30% combined)**: Earlier arrivals and later departures are strong indicators but less direct than total hours, so they share moderate weight.

3. **Non-Workday Work (15%)**: Working weekends/holidays is a clear sign of overcommitment but may be occasional, so moderate weight.

4. **Sustained High Presence (10%)**: Less direct indicator, but when combined with other factors, it's meaningful.

5. **Working While Sick (5%)**: Weakest individual indicator but provides context when other factors are present.

6. **Multi-Factor Bonus**: When multiple overwork indicators align, the risk multiplies (not just adds).

---

## C. Alternative Evaluation Methods

### Recommendation: **Weighted Score + Threshold Multipliers + Multi-Factor Bonus**

**Primary Model: Weighted Linear Combination with Multipliers**
- **Pros**: 
  - Simple, interpretable, fast
  - Easy to tune and explain to stakeholders
  - Allows threshold-based amplification for severe cases
- **Cons**: Assumes some linearity, but acceptable for ranking/risk identification

**Enhancement: Threshold-Based Multipliers**
- Apply multipliers when features exceed critical thresholds
- Example: If hours increase >30%, apply 1.5x multiplier to that component
- Example: If 3+ factors indicate overwork, apply bonus points (up to +10)

**Alternative Methods Considered (but not recommended for initial version):**

1. **Machine Learning (Random Forest/XGBoost)**
   - **Pros**: Could find non-linear patterns and interactions
   - **Cons**: Requires labeled data (employees with known burnout) - we don't have this
   - **Recommendation**: Consider after collecting 6-12 months of validated burnout cases

2. **Statistical Modeling (Logistic Regression)**
   - **Pros**: Provides probability estimates
   - **Cons**: Requires labeled data, harder to interpret for non-statisticians
   - **Recommendation**: Future enhancement after data collection

3. **Anomaly Detection (Isolation Forest)**
   - **Pros**: Can identify outliers without labels
   - **Cons**: Less interpretable, harder to explain "why" an employee is at risk
   - **Recommendation**: Could be used for validation/sanity checking

4. **Rule-Based Systems**
   - **Pros**: Very interpretable
   - **Cons**: Too rigid, misses nuanced patterns
   - **Recommendation**: Current approach already incorporates rule-based elements (thresholds)

---

## D. Model Calculation Method

### Score Calculation Formula:

```
base_score = (hours_score × hours_multiplier) + 
             (arrival_score × arrival_multiplier) + 
             (departure_score × departure_multiplier) + 
             non_workday_score + 
             sustained_presence_score + 
             working_while_sick_score

final_score = MIN(100, base_score + multi_factor_bonus)
```

### Detailed Calculation:

#### 1. Work Hours Increase Score (0 to 40 points)
```sql
hours_delta_pct = (avg_minutes_r - avg_minutes_b) / avg_minutes_b

IF hours_delta_pct > 0 THEN
  hours_score = MIN(40, hours_delta_pct * 100.0 * 40.0)
  
  -- Apply multiplier based on severity
  IF hours_delta_pct > 0.30 THEN hours_multiplier = 1.5  -- Critical: >30% increase
  ELSE IF hours_delta_pct > 0.20 THEN hours_multiplier = 1.3  -- High: >20% increase
  ELSE IF hours_delta_pct > 0.10 THEN hours_multiplier = 1.1  -- Moderate: >10% increase
  ELSE hours_multiplier = 1.0
  
  hours_final = hours_score * hours_multiplier
ELSE
  hours_final = 0
```

#### 2. Earlier Arrival Score (0 to 15 points)
```sql
arrival_delta_minutes = DATEDIFF(MINUTE, avg_arrival_r, avg_arrival_b)  -- Negative = earlier

IF arrival_delta_minutes < -30 THEN  -- Arriving earlier (negative delta)
  arrival_score = MIN(15, ABS(arrival_delta_minutes) / 60.0 * 15.0)
  
  -- Apply multiplier
  IF arrival_delta_minutes < -90 THEN arrival_multiplier = 1.5  -- Critical: >90 min earlier
  ELSE IF arrival_delta_minutes < -60 THEN arrival_multiplier = 1.3  -- High: >60 min earlier
  ELSE arrival_multiplier = 1.1  -- Moderate: >30 min earlier
  
  arrival_final = arrival_score * arrival_multiplier
ELSE
  arrival_final = 0
```

#### 3. Later Departure Score (0 to 15 points)
```sql
departure_delta_minutes = DATEDIFF(MINUTE, avg_departure_b, avg_departure_r)  -- Positive = later

IF departure_delta_minutes > 30 THEN  -- Leaving later (positive delta)
  departure_score = MIN(15, departure_delta_minutes / 60.0 * 15.0)
  
  -- Apply multiplier
  IF departure_delta_minutes > 90 THEN departure_multiplier = 1.5  -- Critical: >90 min later
  ELSE IF departure_delta_minutes > 60 THEN departure_multiplier = 1.3  -- High: >60 min later
  ELSE departure_multiplier = 1.1  -- Moderate: >30 min later
  
  departure_final = departure_score * departure_multiplier
ELSE
  departure_final = 0
```

#### 4. Non-Workday Presence Increase Score (0 to 15 points)
```sql
non_workday_delta = non_workday_presence_r - non_workday_presence_b

IF non_workday_delta > 0 THEN
  non_workday_score = MIN(15, (non_workday_delta / 5.0) * 15.0)  -- Scale: 5 days = 15 points
  
  -- Apply multiplier
  IF non_workday_delta >= 6 THEN non_workday_multiplier = 1.5  -- Critical: 6+ days
  ELSE IF non_workday_delta >= 4 THEN non_workday_multiplier = 1.3  -- High: 4+ days
  ELSE non_workday_multiplier = 1.1  -- Moderate: 2+ days
  
  non_workday_final = non_workday_score * non_workday_multiplier
ELSE
  non_workday_final = 0
```

#### 5. Sustained High Presence Score (0 to 10 points)
```sql
IF presence_pct_r >= 0.90 AND presence_pct_r >= presence_pct_b THEN
  -- High presence maintained or increased (no recovery)
  IF presence_pct_r >= 0.98 THEN sustained_presence_score = 10  -- Critical: >98%
  ELSE IF presence_pct_r >= 0.95 THEN sustained_presence_score = 7  -- High: >95%
  ELSE sustained_presence_score = 4  -- Moderate: >90%
ELSE
  sustained_presence_score = 0
```

#### 6. Working While Sick Pattern Score (0 to 5 points)
```sql
absence_delta_pct = (absence_pct_b - absence_pct_r) / NULLIF(absence_pct_b, 0)
hours_delta_pct = (avg_minutes_r - avg_minutes_b) / NULLIF(avg_minutes_b, 0)

IF absence_delta_pct > 0.20 AND hours_delta_pct > 0.10 THEN
  -- Absence decreased by >20% AND hours increased by >10%
  working_while_sick_score = 5
ELSE IF absence_delta_pct > 0.10 AND hours_delta_pct > 0.05 THEN
  working_while_sick_score = 3
ELSE
  working_while_sick_score = 0
```

#### 7. Multi-Factor Overwork Bonus (0 to +10 points)
```sql
-- Count how many overwork indicators are present
overwork_factors = 
  CASE WHEN hours_delta_pct > 0.10 THEN 1 ELSE 0 END +
  CASE WHEN arrival_delta_minutes < -30 THEN 1 ELSE 0 END +
  CASE WHEN departure_delta_minutes > 30 THEN 1 ELSE 0 END +
  CASE WHEN non_workday_delta > 1 THEN 1 ELSE 0 END +
  CASE WHEN presence_pct_r >= 0.90 AND presence_pct_r >= presence_pct_b THEN 1 ELSE 0 END

IF overwork_factors >= 4 THEN multi_factor_bonus = 10  -- 4+ factors: critical
ELSE IF overwork_factors = 3 THEN multi_factor_bonus = 6  -- 3 factors: high
ELSE IF overwork_factors = 2 THEN multi_factor_bonus = 3  -- 2 factors: moderate
ELSE multi_factor_bonus = 0
```

### Final Score:
```sql
base_score = hours_final + arrival_final + departure_final + 
             non_workday_final + sustained_presence_score + working_while_sick_score

final_score = MIN(100, base_score + multi_factor_bonus)
```

**Score Range: 0-100**
- 0 = No burnout risk indicators
- 100 = Maximum burnout risk (all indicators at critical levels)

---

## E. Risk Level Thresholds for Dashboard

### Recommended Thresholds:

| Risk Level | Score Range | Description | Recommended Action |
|------------|-------------|-------------|-------------------|
| **Low Risk** | 0-29 | Minimal burnout indicators | Monitor quarterly |
| **Medium Risk** | 30-49 | Some overwork patterns emerging | Monthly check-ins, workload review |
| **High Risk** | 50-69 | Clear burnout indicators present | Weekly check-ins, workload reduction, wellness support |
| **Critical Risk** | 70-100 | Severe burnout risk, immediate intervention needed | Immediate intervention, mandatory time off consideration, HR/manager involvement |

### Threshold Rationale:

**Low (0-29):**
- Minimal or no overwork indicators
- May have 1-2 minor indicators but not concerning
- Normal work patterns maintained

**Medium (30-49):**
- 2-3 moderate indicators present
- Some concerning patterns emerging
- Early intervention can prevent escalation

**High (50-69):**
- 3-4 indicators present, some at high levels
- Clear pattern of overwork
- Active burnout risk requiring intervention

**Critical (70-100):**
- 4+ indicators present, many at critical levels
- Severe overwork pattern
- Immediate intervention required to prevent burnout

### Adjustability:

All thresholds should be configurable via `risk_config` table:
- `burnout_threshold_low`: Default 30
- `burnout_threshold_medium`: Default 50
- `burnout_threshold_high`: Default 70

This allows clients to adjust sensitivity based on their industry, culture, and risk tolerance.

---

## F. Key Differences from Flight Risk Model

| Aspect | Flight Risk (Disengagement) | Burnout Risk (Overwork) |
|--------|----------------------------|-------------------------|
| **Core Pattern** | Withdrawal, reduced commitment | Overcommitment, excessive work |
| **Hours Change** | DECREASE (reduced hours) | INCREASE (more hours) |
| **Arrival Pattern** | LATER (disengagement) | EARLIER (overcommitment) |
| **Departure Pattern** | EARLIER (early exit) | LATER (staying late) |
| **Presence Pattern** | DECLINE (missing work) | HIGH/STABLE (working too much) |
| **Non-Workday** | Change (could go either way) | INCREASE (working weekends) |
| **Absence Pattern** | INCREASE (more absences) | DECREASE (working while sick) |
| **Primary Indicator** | Attendance decline | Hours increase |

**Critical Insight:** These models detect opposite patterns - one indicates withdrawal (flight risk), the other indicates overcommitment (burnout risk). An employee could theoretically be at high risk for both if they're working excessive hours while simultaneously disengaging (a pattern sometimes seen in late-stage burnout).

---

## G. Implementation Considerations

### Data Requirements:
- Requires `calc_period_metrics` table to be populated via `usp_calc_periods`
- Baseline and recent periods should be properly configured (typically 9 months baseline, 3 months recent)

### Performance:
- Should run after `usp_calc_periods` completes
- Can be optimized with indexes on `calc_period_metrics(client_id, emp_id)`

### Configurability:
All weights, thresholds, and multipliers should be configurable via `risk_config` table:
- Feature weights
- Threshold multipliers
- Risk level boundaries
- Minimum data requirements

### Validation:
- Run both models in parallel for 3-6 months
- Collect feedback from managers/HR on accuracy
- Adjust weights/thresholds based on real-world validation
- Consider A/B testing different weight configurations

---

## H. Example Calculations

### Example 1: Moderate Burnout Risk Employee

**Employee A:**
- Hours: 450 min baseline → 520 min recent (15.6% increase)
- Arrival: 8:00 AM baseline → 7:30 AM recent (30 min earlier)
- Departure: 5:00 PM baseline → 5:30 PM recent (30 min later)
- Non-workday presence: 2 baseline → 3 recent (+1 day)
- Presence: 92% baseline → 94% recent (high and increasing)
- Absence: 5% baseline → 3% recent (declining)

**Calculation:**
```
hours_score = 15.6% * 100 * 40 = 6.24 * 1.1 (moderate multiplier) = 6.86
arrival_score = 30/60 * 15 = 7.5 * 1.1 = 8.25
departure_score = 30/60 * 15 = 7.5 * 1.1 = 8.25
non_workday_score = 1/5 * 15 = 3 * 1.1 = 3.3
sustained_presence = 4 (90-95% range)
working_while_sick = 0 (conditions not met)

base_score = 6.86 + 8.25 + 8.25 + 3.3 + 4 + 0 = 30.66

overwork_factors = 1 + 1 + 1 + 1 + 1 = 5 factors
multi_factor_bonus = 10

final_score = MIN(100, 30.66 + 10) = 40.66 → 41
```

**Result: Medium Risk (41 points)** - Clear overwork pattern emerging, intervention recommended.

---

### Example 2: Critical Burnout Risk Employee

**Employee B:**
- Hours: 420 min baseline → 600 min recent (42.9% increase)
- Arrival: 8:30 AM baseline → 6:45 AM recent (105 min earlier)
- Departure: 5:30 PM baseline → 7:15 PM recent (105 min later)
- Non-workday presence: 1 baseline → 8 recent (+7 days)
- Presence: 88% baseline → 96% recent (very high)
- Absence: 8% baseline → 2% recent (significant decline)

**Calculation:**
```
hours_score = 42.9% * 100 * 40 = 17.16 * 1.5 (critical) = 25.74 (capped at 40)
arrival_score = 105/60 * 15 = 26.25 * 1.5 = 39.38 (capped at 15) = 15
departure_score = 105/60 * 15 = 26.25 * 1.5 = 39.38 (capped at 15) = 15
non_workday_score = 7/5 * 15 = 21 * 1.5 = 31.5 (capped at 15) = 15
sustained_presence = 7 (95%+ range)
working_while_sick = 5 (strong pattern)

base_score = 25.74 + 15 + 15 + 15 + 7 + 5 = 82.74

overwork_factors = 1 + 1 + 1 + 1 + 1 + 1 = 6 factors
multi_factor_bonus = 10

final_score = MIN(100, 82.74 + 10) = 92.74 → 93
```

**Result: Critical Risk (93 points)** - Severe burnout risk, immediate intervention required.

---

## I. Summary

This burnout risk model:

✅ Uses research-backed indicators of overwork and burnout  
✅ Identifies employees at risk based on excessive hours, time pattern changes, and unsustainable work patterns  
✅ Provides a 0-100 risk score with clear thresholds  
✅ Is configurable via `risk_config` table  
✅ Is distinct from flight risk model (detects overwork vs disengagement)  
✅ Uses weighted scoring with threshold multipliers and multi-factor bonuses  
✅ Provides actionable risk levels for dashboard visualization  

The model is designed to identify employees most likely to be experiencing burnout, enabling proactive intervention before burnout becomes severe.

