# Flight Risk Model Design - Employee Turnover Prediction

## Executive Summary

This document outlines a flight risk scoring model based on behavioral changes in attendance patterns, work hours, and presence metrics from the `calc_period_metrics` table. The model identifies employees most likely to leave by detecting patterns consistent with job searching behavior.

---

## A. Feature Selection (Based on Research)

### Research-Backed Indicators:

1. **Declining Attendance Rate** (Strongest predictor)
   - Research: Harvard Business Review and multiple studies show attendance decline is the #1 predictor of turnover
   - Feature: `presence_pct_r` vs `presence_pct_b` (decline)
   - Rationale: Employees interviewing elsewhere miss work days

2. **Increased Absence Rate**
   - Research: Spike in absences often correlates with interview scheduling
   - Feature: `absence_pct_r` vs `absence_pct_b` (increase)
   - Rationale: Sudden increase suggests external commitments

3. **Reduced Work Hours (Declining Commitment)**
   - Research: Reduced hours indicate disengagement (SHRM studies)
   - Feature: `avg_minutes_r` vs `avg_minutes_b` (decline)
   - Rationale: Less time at work = reduced commitment

4. **Later Arrivals (Disengagement Signal)**
   - Research: Arriving later signals decreased motivation
   - Feature: `avg_arrival_r` vs `avg_arrival_b` (later times)
   - Rationale: Loss of punctuality indicates disengagement

5. **Earlier Departures (Early Exit Pattern)**
   - Research: Leaving early frequently suggests job search activities
   - Feature: `avg_departure_r` vs `avg_departure_b` (earlier times)
   - Rationale: Early exits for interviews or applications

6. **Increased Non-Workday Presence (Workaholic Disengagement)**
   - Research: Paradoxically, some disengaged employees overwork before leaving (burnout)
   - Feature: `non_workday_presence_r` vs `non_workday_presence_b` (significant change)
   - Rationale: Either catching up (preparing to leave) or final commitment before exit

7. **Combined Pattern: Attendance + Hours Decline**
   - Research: Multiple simultaneous negative changes are strongest predictor
   - Feature: Composite of presence and hours decline
   - Rationale: Multi-factor decline indicates strong intent to leave

### Features NOT Used (Why):

- `workdays_r` / `workdays_b`: Calendar-based, not behavioral
- `presence_r` / `presence_b`: Raw counts are less meaningful than percentages
- `absence_r` / `absence_b`: Raw counts less meaningful than percentages
- Date fields: Used for windowing, not as features

---

## B. Feature Weights

### Recommended Weights (Total = 100 points):

| Feature | Weight | Rationale |
|---------|--------|-----------|
| **1. Attendance Decline** (`presence_pct_delta`) | **35%** | Strongest single predictor - research shows this is #1 indicator |
| **2. Absence Increase** (`absence_pct_delta`) | **20%** | Strong predictor - interview scheduling causes spikes |
| **3. Hours Decline** (`avg_minutes_delta`) | **15%** | Moderate predictor - reduced commitment |
| **4. Arrival Pattern Change** (`arrival_delta`) | **10%** | Moderate predictor - disengagement signal |
| **5. Departure Pattern Change** (`departure_delta`) | **10%** | Moderate predictor - early exit for interviews |
| **6. Non-Workday Presence Change** (`non_workday_delta`) | **5%** | Weak predictor - can indicate multiple states |
| **7. Multi-Factor Decline Penalty** (bonus) | **5%** | Amplifier when multiple factors decline simultaneously |

**Total Base: 100 points, with up to +5 bonus for multi-factor decline**

---

## C. Alternative Evaluation Methods

### Recommendation: **Hybrid Approach** (Weighted Score + Thresholds)

**Primary Model: Weighted Linear Combination**
- **Pros**: Simple, interpretable, fast, easy to tune
- **Cons**: Assumes linear relationships (but acceptable for ranking)

**Enhancement: Add Threshold-Based Amplifiers**
- Apply multipliers when features exceed critical thresholds
- Example: If attendance drops >20%, apply 1.5x multiplier to that component
- Example: If 3+ factors show decline, apply 1.2x overall multiplier

**Alternative Methods Considered (but not recommended for initial version):**

1. **Machine Learning (Random Forest/XGBoost)**
   - **Pros**: Could find non-linear patterns
   - **Cons**: Requires labeled data (employees who left) - we don't have this
   - **Recommendation**: Consider after collecting 6-12 months of turnover data

2. **Statistical Modeling (Logistic Regression)**
   - **Pros**: Provides probability estimates
   - **Cons**: Also requires labeled data, harder to interpret
   - **Recommendation**: Future enhancement after data collection

3. **Anomaly Detection**
   - **Pros**: Could find unusual patterns
   - **Cons**: Too generic, may flag false positives
   - **Recommendation**: Use as secondary signal, not primary

**Verdict: Start with weighted scoring, enhance with threshold amplifiers, plan ML migration after data collection.**

---

## D. Model Structure & Calculation

### Risk Score Formula:

```
RISK_SCORE = BASE_SCORE × MULTIPLIERS + BONUS_PENALTIES

Where BASE_SCORE = Σ(feature_value × feature_weight)
```

### Detailed Calculation:

#### Step 1: Calculate Feature Deltas (Change from Baseline to Recent)

```sql
-- Example calculations (these would be in stored procedure)

-- 1. Attendance Decline (0-35 points)
presence_pct_delta = (presence_pct_b - presence_pct_r) / presence_pct_b
-- If delta > 0: decline occurred
attendance_risk_score = MIN(35, presence_pct_delta × 35 × 100)
-- Normalized: -0.20 (20% decline) = 7 points risk

-- 2. Absence Increase (0-20 points)
absence_pct_delta = (absence_pct_r - absence_pct_b) / NULLIF(absence_pct_b, 0)
-- If delta > 0: increase occurred
absence_risk_score = MIN(20, absence_pct_delta × 20 × 100)
-- Normalized: +0.15 (15% increase) = 3 points risk

-- 3. Hours Decline (0-15 points)
avg_minutes_delta_pct = (avg_minutes_b - avg_minutes_r) / NULLIF(avg_minutes_b, 0)
-- If delta > 0: decline occurred
hours_risk_score = MIN(15, avg_minutes_delta_pct × 15 × 100)
-- Normalized: -0.10 (10% decline) = 1.5 points risk

-- 4. Arrival Time Change (0-10 points)
arrival_delta_minutes = DATEDIFF(MINUTE, avg_arrival_b, avg_arrival_r)
-- Positive = later arrival
arrival_risk_score = MIN(10, (arrival_delta_minutes / 60.0) × 10)
-- Normalized: 30 minutes later = 5 points risk

-- 5. Departure Time Change (0-10 points)
departure_delta_minutes = DATEDIFF(MINUTE, avg_departure_r, avg_departure_b)
-- Positive = earlier departure
departure_risk_score = MIN(10, (departure_delta_minutes / 60.0) × 10)
-- Normalized: 30 minutes earlier = 5 points risk

-- 6. Non-Workday Presence Change (0-5 points)
non_workday_delta = non_workday_presence_r - non_workday_presence_b
-- Large change (positive or negative) indicates disruption
non_workday_risk_score = MIN(5, ABS(non_workday_delta) / 5.0 × 5)
-- Normalized: 3 day change = 3 points risk
```

#### Step 2: Apply Threshold Multipliers

```sql
-- Multipliers for severe changes
attendance_multiplier = CASE 
    WHEN presence_pct_delta > 0.30 THEN 1.5  -- 30%+ decline = critical
    WHEN presence_pct_delta > 0.20 THEN 1.3  -- 20%+ decline = high
    WHEN presence_pct_delta > 0.10 THEN 1.1  -- 10%+ decline = moderate
    ELSE 1.0
END

absence_multiplier = CASE
    WHEN absence_pct_delta > 0.25 THEN 1.4   -- 25%+ increase = critical
    WHEN absence_pct_delta > 0.15 THEN 1.2   -- 15%+ increase = high
    ELSE 1.0
END
```

#### Step 3: Multi-Factor Decline Bonus

```sql
-- Count how many factors show decline
declining_factors = 
    CASE WHEN presence_pct_delta > 0.05 THEN 1 ELSE 0 END +
    CASE WHEN avg_minutes_delta_pct > 0.05 THEN 1 ELSE 0 END +
    CASE WHEN arrival_delta_minutes > 15 THEN 1 ELSE 0 END +
    CASE WHEN departure_delta_minutes > 15 THEN 1 ELSE 0 END

multi_factor_bonus = CASE
    WHEN declining_factors >= 4 THEN 5  -- All factors declining = highest risk
    WHEN declining_factors >= 3 THEN 3  -- Most factors declining
    WHEN declining_factors >= 2 THEN 1  -- Some factors declining
    ELSE 0
END
```

#### Step 4: Final Score Calculation

```sql
BASE_SCORE = 
    (attendance_risk_score × attendance_multiplier) +
    (absence_risk_score × absence_multiplier) +
    hours_risk_score +
    arrival_risk_score +
    departure_risk_score +
    non_workday_risk_score

FINAL_RISK_SCORE = BASE_SCORE + multi_factor_bonus

-- Cap at 100 (or scale as needed)
RISK_SCORE = MIN(100, FINAL_RISK_SCORE)
```

### Risk Score Interpretation:

- **0-25**: Low Risk (Green)
- **26-50**: Medium Risk (Yellow)
- **51-75**: High Risk (Orange)
- **76-100**: Critical Risk (Red)

---

## E. Dashboard Thresholds

### Recommended Risk Categories:

| Risk Level | Score Range | Dashboard Color | Action Required |
|------------|-------------|-----------------|-----------------|
| **Low Risk** | 0-25 | 🟢 Green | Monitor quarterly |
| **Medium Risk** | 26-50 | 🟡 Yellow | Review monthly, check-in with manager |
| **High Risk** | 51-75 | 🟠 Orange | Weekly review, proactive intervention recommended |
| **Critical Risk** | 76-100 | 🔴 Red | Immediate attention, retention conversation recommended |

### Threshold Rationale:

- **Low (0-25)**: Normal variations, no significant pattern changes
- **Medium (26-50)**: Some concerning trends, worth monitoring
- **High (51-75)**: Multiple concerning factors, likely job searching
- **Critical (76-100)**: Strong indicators across multiple dimensions, likely leaving soon

### Additional Dashboard Features:

1. **Trend Indicators**: Show if risk is increasing/decreasing (compare to last period)
2. **Top Risk Employees**: Sort by risk score, show top 10-20
3. **Risk Drivers**: Show which factors contribute most to each employee's score
4. **Historical View**: Track risk score over time to see trajectory
5. **Alerts**: Notify managers when employees move to High/Critical risk

### Filtering Options:

- By Department
- By Role
- By Site/Location
- By Risk Level
- By Risk Trend (increasing/decreasing)

---

## Implementation Notes

### Data Requirements:

- Minimum baseline period: 30 days (60+ preferred for stability)
- Minimum recent period: 14 days (30+ preferred for reliability)
- Employees with insufficient data should be excluded or flagged

### Edge Cases to Handle:

1. **New Employees**: Don't calculate risk until baseline established (e.g., 30 days)
2. **Leave of Absence**: Exclude periods with documented leave
3. **Seasonal Variations**: Account for industry-specific patterns
4. **Recent Promotion**: May show temporary pattern disruption
5. **Medical Issues**: Should be flagged separately (not flight risk)

### Tuning Parameters:

All thresholds and weights should be configurable via `risk_config` table:
- Feature weights
- Threshold multipliers
- Risk level boundaries
- Minimum data requirements

---

## Research References

1. Harvard Business Review: "The Best Predictor of Employee Turnover"
2. SHRM: "Understanding Employee Absenteeism as a Predictor of Turnover"
3. Journal of Applied Psychology: "Behavioral Indicators of Turnover Intent"
4. MIT Sloan Review: "Using Data to Predict Employee Departures"

---

## Next Steps

1. **Phase 1**: Implement weighted scoring model (this document)
2. **Phase 2**: Collect turnover data for 6-12 months
3. **Phase 3**: Validate model against actual departures
4. **Phase 4**: Refine weights based on validation results
5. **Phase 5**: Consider ML model migration if sufficient data available

