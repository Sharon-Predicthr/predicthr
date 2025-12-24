SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.calc_fraud_metrics') AND type = 'U')
BEGIN 
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
  
  -- Peer group statistics (for reference/debugging)
  peer_group_size       INT            NOT NULL,
  peer_group_type       NVARCHAR(50)   NULL,  -- 'dept_role', 'dept_only', 'client_wide'
  peer_mean_door_mismatch FLOAT        NULL,
  peer_mean_pingpong      FLOAT        NULL,
  peer_mean_odd_hours     FLOAT        NULL,
  peer_mean_session_length FLOAT       NULL,
  peer_mean_sessions_per_day FLOAT     NULL,
  
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

CREATE INDEX IX_calc_fraud_metrics_client_dept_role
  ON dbo.calc_fraud_metrics(client_id, department, emp_role, fraud_risk_score DESC);
END
GO

