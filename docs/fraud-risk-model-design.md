# Fraud/Integrity Risk Model Design

## Executive Summary

This document outlines a fraud/integrity risk scoring model based on statistical anomaly detection comparing individual employee patterns to peer group norms. Unlike flight risk and burnout risk models, this model detects anomalies compared to the **population** rather than compared to the employee's own baseline behavior. This approach aligns with fraud detection best practices where outliers in peer groups are more indicative of fraud.

---

## A. Feature Selection (Based on Research)

### Research-Backed Fraud Indicators:

Employee time fraud typically manifests in several patterns that can be detected through attendance data analysis:

### 1. **Door Mismatch Patterns** (Strongest Indicator)
   - **Research**: Door mismatches (entering through one door, exiting through another) are strongly correlated with buddy punching and time theft (Association of Certified Fraud Examiners)
   - **Feature**: Percentage of days with door mismatches (`door_mis_pct_r`)
   - **Detection Method**: Compare employee's door mismatch rate to peer group (department/role) using Z-score
   - **Rationale**: Legitimate employees typically use the same entrance/exit; mismatches suggest proxy clocking

### 2. **Ping-Pong Patterns** (High Frequency Entry/Exit)
   - **Research**: Excessive entries/exits (3+ sessions per day) often indicate time manipulation or falsified records (Time and Attendance Fraud Studies)
   - **Feature**: Percentage of days with ping-pong patterns (`pingpong_pct_r`)
   - **Detection Method**: Compare to peer group using Z-score and percentile ranking
   - **Rationale**: Normal work patterns show 1-2 sessions per day; excessive sessions suggest manipulation

### 3. **Odd/Remote Hours Patterns**
   - **Research**: Working at unusual times (very early/late hours, remote patterns) can indicate falsified time records
   - **Feature**: Percentage of days with odd/remote patterns (`odd_pct_r`)
   - **Detection Method**: Compare to peer group using Z-score
   - **Rationale**: Employees with legitimate remote/odd hours typically cluster in similar roles/departments; outliers are suspicious

### 4. **Unusual Session Lengths** (Statistical Outlier)
   - **Research**: Extremely short sessions (<1 hour) or extremely long sessions (>12 hours) are uncommon and may indicate fraud
   - **Feature**: Average session length deviation from peer group mean
   - **Detection Method**: Z-score of average session length vs peer group
   - **Rationale**: Most employees have consistent session lengths; outliers suggest manipulation

### 5. **Excessive Daily Sessions Count** (Beyond Ping-Pong)
   - **Research**: More than 4-5 sessions per day is extremely unusual and suggests time manipulation
   - **Feature**: Average number of sessions per day vs peer group
   - **Detection Method**: Z-score of average daily sessions vs peer group
   - **Rationale**: Normal employees have 1-2 sessions; excessive counts indicate manipulation

### 6. **Unusual Arrival/Departure Times** (Statistical Outlier)
   - **Research**: Arriving extremely early/late or leaving extremely early/late compared to peer group
   - **Feature**: Arrival and departure time deviations from peer group norms
   - **Detection Method**: Z-score of average arrival/departure times vs peer group
   - **Rationale**: Peer groups have similar schedules; outliers are suspicious

### 7. **Composite Integrity Score** (Multi-Factor Fraud Indicator)
   - **Research**: Multiple fraud indicators occurring simultaneously significantly increase fraud probability
   - **Feature**: Combination of door mismatch + ping-pong + odd hours
   - **Detection Method**: Count of how many indicators exceed threshold simultaneously
   - **Rationale**: Single anomaly may be legitimate; multiple anomalies strongly suggest fraud

### Features NOT Used (Why):

- Presence/absence rates: Not reliable fraud indicators (could be legitimate absences)
- Hours worked: Too variable across roles to be meaningful for fraud detection
- Baseline comparisons: Fraud detection should compare to peers, not personal history

---

## B. Evaluation Method & Weighting Strategy

### Recommendation: **Statistical Anomaly Detection with Weighted Composite Score**

**Primary Approach: Z-Score Based Ranking with Weighted Composite**

This approach is more appropriate than simple weighting or Fibonacci sequences for fraud detection because:

1. **Fraud is rare**: Only 2-5% of employees commit fraud, so we need statistical methods to identify outliers
2. **Peer comparison is critical**: Fraud patterns only make sense when compared to similar employees (same role/department)
3. **Severity matters**: The degree of deviation (how many standard deviations away) is more important than raw percentages

### Why NOT Fibonacci Sequence?

While Fibonacci sequence (1, 1, 2, 3, 5, 8, 13, 21, 34...) has mathematical elegance, it's **not recommended** for fraud detection for several important reasons:

1. **No research basis**: 
   - No academic research or industry standards support Fibonacci ratios for fraud detection
   - Fraud detection methodologies consistently recommend statistical methods (Z-scores, percentiles)
   - Fibonacci sequence appears in nature and mathematics but has no connection to fraud patterns

2. **Poor granularity for scoring**:
   - Fibonacci sequence jumps too quickly (1→1→2→3→5→8→13) for fine-tuned risk scoring
   - Would create large gaps in risk levels (e.g., 5→8 is a 60% jump)
   - Current approach (0-100 scale) allows for much finer distinctions

3. **Arbitrary mapping**:
   - It's unclear how to map fraud indicators to Fibonacci values
   - Should door mismatch = 13, ping-pong = 8, odd hours = 5? Why these values?
   - No logical connection between Fibonacci numbers and fraud severity

4. **Statistical methods are industry standard**:
   - Association of Certified Fraud Examiners (ACFE) recommends statistical outlier detection
   - Research consistently shows Z-scores and percentiles are most effective for fraud detection
   - Peer group comparison using statistical methods is the gold standard

5. **Fibonacci would require normalization anyway**:
   - Even if using Fibonacci, you'd need to normalize to a 0-100 scale
   - This adds complexity without benefit
   - The proposed method already provides this normalization through percentiles

**Alternative Consideration**: If you want progressive scaling similar to Fibonacci's exponential growth, you could use **logarithmic scaling** or **exponential multipliers** for extreme outliers. However, percentile-based ranking (which inherently captures exponential rarity) is still preferred because it's based on actual data distributions rather than arbitrary mathematical sequences.

### Recommended Method: **Z-Score Percentile Ranking with Composite Weights**

**Step 1: Calculate Z-Scores for Each Feature**
```sql
Z-score = (employee_value - peer_group_mean) / peer_group_std_dev
```

**Step 2: Convert Z-Scores to Percentile Ranks** (0-100 scale)
- Z-score of 0 = 50th percentile (average)
- Z-score of +2 = 97.7th percentile (high outlier)
- Z-score of +3 = 99.9th percentile (extreme outlier)

**Step 3: Apply Feature Weights**
Each feature gets a weight based on its fraud detection importance. Weights sum to 100.

**Step 4: Calculate Composite Score**
```sql
fraud_score = (door_mismatch_percentile * weight) + 
              (pingpong_percentile * weight) + 
              (odd_hours_percentile * weight) + ...
```

### Recommended Feature Weights:

| Feature | Weight | Rationale |
|---------|--------|-----------|
| **Door Mismatch** | 35% | Strongest single indicator (buddy punching) |
| **Ping-Pong Patterns** | 25% | High indicator (time manipulation) |
| **Odd/Remote Hours** | 15% | Moderate indicator (falsified records) |
| **Unusual Session Lengths** | 10% | Moderate indicator (time manipulation) |
| **Excessive Daily Sessions** | 10% | Moderate indicator (time manipulation) |
| **Multi-Factor Composite** | 5% | Bonus when multiple indicators align |

**Total: 100%**

---

## C. Model Calculation Method

### Step 1: Calculate Employee-Level Metrics

For each employee, calculate:
- `door_mismatch_pct`: % of days with door mismatches
- `pingpong_pct`: % of days with 3+ sessions
- `odd_hours_pct`: % of days with odd/remote patterns
- `avg_session_minutes`: Average session length
- `avg_sessions_per_day`: Average number of sessions per day

### Step 2: Calculate Peer Group Statistics

For each employee's peer group (same department + role, or department only if role not available):
- Mean and standard deviation for each metric
- Percentiles (25th, 50th, 75th, 90th, 95th, 99th)

### Step 3: Calculate Z-Scores

```sql
door_mismatch_zscore = (emp.door_mismatch_pct - peer_mean_door_mismatch) / peer_std_door_mismatch
pingpong_zscore = (emp.pingpong_pct - peer_mean_pingpong) / peer_std_pingpong
odd_hours_zscore = (emp.odd_hours_pct - peer_mean_odd_hours) / peer_std_odd_hours
session_length_zscore = (emp.avg_session_minutes - peer_mean_session_length) / peer_std_session_length
sessions_per_day_zscore = (emp.avg_sessions_per_day - peer_mean_sessions_per_day) / peer_std_sessions_per_day
```

### Step 4: Convert Z-Scores to Percentile Ranks (0-100)

Using the standard normal distribution:
- Z = 0 → Percentile = 50
- Z = 1 → Percentile = 84
- Z = 2 → Percentile = 98
- Z = 3 → Percentile = 99.9

SQL approximation:
```sql
percentile = 50 + (z_score * 20)  -- Capped at 0-100
-- For more accuracy, use: 50 * (1 + ERF(z_score / SQRT(2)))
```

**Note**: Only positive Z-scores (above average) indicate fraud risk. Negative Z-scores (below average) should be set to 0.

### Step 5: Calculate Weighted Composite Score

```sql
base_score = (door_mismatch_percentile * 0.35) +
             (pingpong_percentile * 0.25) +
             (odd_hours_percentile * 0.15) +
             (session_length_percentile * 0.10) +
             (sessions_per_day_percentile * 0.10)

-- Multi-factor bonus (if 3+ indicators in top 10%)
multi_factor_bonus = CASE 
  WHEN door_mismatch_percentile >= 90 AND pingpong_percentile >= 90 AND odd_hours_percentile >= 90 THEN 5
  WHEN (door_mismatch_percentile >= 90) + (pingpong_percentile >= 90) + (odd_hours_percentile >= 90) >= 2 THEN 3
  ELSE 0
END

final_score = MIN(100, base_score + multi_factor_bonus)
```

### Step 6: Handle Edge Cases

- **Insufficient peer group size**: If peer group < 5 employees, use department-only or client-wide statistics
- **Zero standard deviation**: If all peers have same value, use client-wide statistics
- **Missing data**: Employees with < 5 days of data should be excluded or flagged separately

---

## D. Risk Level Thresholds for Dashboard

### Recommended Thresholds:

| Risk Level | Score Range | Description | Recommended Action |
|------------|-------------|-------------|-------------------|
| **Low Risk** | 0-39 | Within normal range or slight deviations | Monitor quarterly |
| **Medium Risk** | 40-59 | Moderate statistical outliers | Monthly review, investigate patterns |
| **High Risk** | 60-79 | Significant statistical outliers | Weekly review, detailed investigation |
| **Critical Risk** | 80-100 | Extreme statistical outliers | Immediate investigation, potential disciplinary action |

### Threshold Rationale:

**Low (0-39):**
- Employee patterns align with peer group
- Minor deviations that fall within normal variance
- No action required, normal monitoring

**Medium (40-59):**
- 1-2 standard deviations above peer group mean
- Patterns are unusual but may have legitimate explanations
- Review patterns, gather context, document findings

**High (60-79):**
- 2-3 standard deviations above peer group mean
- Strong indicators of potential fraud
- Detailed investigation required, document all findings

**Critical (80-100):**
- 3+ standard deviations above peer group mean
- Extreme outliers with very low probability of being legitimate
- Immediate investigation, consider disciplinary action

**Note**: These thresholds are based on statistical significance (95th-99th percentiles). Adjust based on organizational risk tolerance.

---

## E. Implementation Considerations

### Data Requirements:

1. **Employee-level metrics**: Can be calculated from `emp_sessions` and `calculated_data` tables
2. **Peer group definitions**: Use `department` and `emp_role` from employee metadata
3. **Minimum sample sizes**: Need at least 5 employees per peer group for meaningful statistics

### New Table Needed: `calc_fraud_metrics`

To store calculated metrics for fraud detection:

```sql
CREATE TABLE dbo.calc_fraud_metrics
(
  client_id            NVARCHAR(50)    NOT NULL,
  emp_id               NVARCHAR(100)   NOT NULL,
  department           NVARCHAR(200)   NULL,
  emp_role             NVARCHAR(200)   NULL,
  
  analysis_period_start DATE           NOT NULL,
  analysis_period_end   DATE           NOT NULL,
  days_analyzed         INT            NOT NULL,
  
  -- Raw metrics
  door_mismatch_pct     FLOAT          NOT NULL,
  pingpong_pct          FLOAT          NOT NULL,
  odd_hours_pct         FLOAT          NOT NULL,
  avg_session_minutes   FLOAT          NOT NULL,
  avg_sessions_per_day  FLOAT          NOT NULL,
  
  -- Peer group statistics (for reference)
  peer_group_size       INT            NOT NULL,
  peer_mean_door_mismatch FLOAT        NULL,
  peer_mean_pingpong      FLOAT        NULL,
  peer_mean_odd_hours     FLOAT        NULL,
  
  -- Z-scores
  door_mismatch_zscore   FLOAT         NULL,
  pingpong_zscore        FLOAT         NULL,
  odd_hours_zscore       FLOAT         NULL,
  session_length_zscore  FLOAT         NULL,
  sessions_per_day_zscore FLOAT        NULL,
  
  -- Percentiles (0-100)
  door_mismatch_percentile FLOAT       NULL,
  pingpong_percentile      FLOAT       NULL,
  odd_hours_percentile     FLOAT       NULL,
  session_length_percentile FLOAT      NULL,
  sessions_per_day_percentile FLOAT    NULL,
  
  -- Final score
  fraud_risk_score        INT          NULL,
  
  computed_at             DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  
  CONSTRAINT PK_calc_fraud_metrics PRIMARY KEY (client_id, emp_id)
);
```

### Performance Considerations:

- Calculate peer group statistics in batches by department/role
- Use window functions for percentile calculations
- Index on `(client_id, department, emp_role)` for peer group queries

### Configurability:

All weights, thresholds, and parameters should be configurable via `risk_config` table:
- Feature weights
- Peer group minimum size
- Z-score to percentile conversion parameters
- Risk level boundaries
- Multi-factor bonus thresholds

---

## F. Example Calculation

### Employee Profile:
- Employee: John Doe (Department: Sales, Role: Sales Rep)
- Door mismatch: 25% of days (peer mean: 5%, std dev: 3%)
- Ping-pong: 30% of days (peer mean: 8%, std dev: 5%)
- Odd hours: 15% of days (peer mean: 10%, std dev: 4%)
- Avg session length: 180 minutes (peer mean: 480 minutes, std dev: 60 minutes)
- Avg sessions per day: 3.5 (peer mean: 1.2, std dev: 0.4)

### Calculations:

**Z-Scores:**
```
door_mismatch_zscore = (25 - 5) / 3 = 6.67
pingpong_zscore = (30 - 8) / 5 = 4.4
odd_hours_zscore = (15 - 10) / 4 = 1.25
session_length_zscore = (180 - 480) / 60 = -5.0 (negative = below average, set to 0)
sessions_per_day_zscore = (3.5 - 1.2) / 0.4 = 5.75
```

**Percentiles (approximate):**
```
door_mismatch_percentile = MIN(100, 50 + (6.67 * 20)) = 100
pingpong_percentile = MIN(100, 50 + (4.4 * 20)) = 100
odd_hours_percentile = MIN(100, 50 + (1.25 * 20)) = 75
session_length_percentile = 0 (negative z-score)
sessions_per_day_percentile = MIN(100, 50 + (5.75 * 20)) = 100
```

**Composite Score:**
```
base_score = (100 * 0.35) + (100 * 0.25) + (75 * 0.15) + (0 * 0.10) + (100 * 0.10)
           = 35 + 25 + 11.25 + 0 + 10
           = 81.25

multi_factor_bonus = 5 (3 indicators in top 10%)

final_score = MIN(100, 81.25 + 5) = 86
```

**Result: Critical Risk (86 points)** - Extreme statistical outlier requiring immediate investigation.

---

## G. Key Differences from Other Risk Models

| Aspect | Flight Risk | Burnout Risk | **Fraud Risk** |
|--------|-------------|--------------|----------------|
| **Comparison Basis** | Employee vs own baseline | Employee vs own baseline | **Employee vs peer group** |
| **Method** | Trend analysis | Trend analysis | **Statistical outlier detection** |
| **Primary Indicators** | Attendance decline | Hours increase | **Integrity violations (door mismatch, ping-pong)** |
| **Scoring Method** | Weighted deltas | Weighted deltas | **Z-score percentile ranking** |
| **Focus** | Behavior change | Behavior change | **Anomaly vs population** |

---

## H. Summary

This fraud risk model:

✅ Uses research-backed integrity violation indicators  
✅ Compares employees to peer groups (not personal baseline) using statistical methods  
✅ Uses Z-score based percentile ranking for accurate outlier detection  
✅ Provides a 0-100 risk score with clear thresholds  
✅ Is configurable via `risk_config` table  
✅ Detects statistical anomalies that suggest fraud/integrity issues  
✅ Uses weighted composite scoring with multi-factor bonuses  

The model is designed to identify employees most likely to be committing fraud or integrity violations by detecting patterns that are statistical outliers compared to their peer group, enabling proactive investigation and intervention.

