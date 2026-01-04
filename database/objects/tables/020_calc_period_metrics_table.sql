SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.calc_period_metrics') AND type = 'U')
BEGIN 
CREATE TABLE dbo.calc_period_metrics
(
  client_id            NVARCHAR(50)    NOT NULL,
  emp_id               NVARCHAR(100)   NOT NULL,

  recent_start         DATE            NOT NULL,
  recent_end           DATE            NOT NULL,

  baseline_start       DATE            NOT NULL,
  baseline_end         DATE            NOT NULL,

  workdays_r           INT             NOT NULL,
  workdays_b           INT             NOT NULL,

  presence_r           INT             NOT NULL,
  presence_b           INT             NOT NULL,

  presence_pct_r       FLOAT           NOT NULL,
  presence_pct_b       FLOAT           NOT NULL,

  avg_minutes_r        FLOAT           NOT NULL,
  avg_minutes_b        FLOAT           NOT NULL,

  avg_arrival_r        TIME            NOT NULL,
  avg_arrival_b        TIME            NOT NULL,

  avg_departure_r      TIME            NOT NULL,
  avg_departure_b      TIME            NOT NULL,

  absence_r            INT             NOT NULL,
  absence_b            INT             NOT NULL,

  absence_pct_r        FLOAT           NOT NULL,
  absence_pct_b        FLOAT           NOT NULL, 

  non_workday_presence_r INT           NOT NULL,
  non_workday_presence_b INT           NOT NULL
);
END
GO

-- Create indexes for client_id and emp_id
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_calc_period_metrics_client_id' AND object_id = OBJECT_ID('dbo.calc_period_metrics'))
BEGIN
  CREATE INDEX IX_calc_period_metrics_client_id ON dbo.calc_period_metrics (client_id);
END
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_calc_period_metrics_emp_id' AND object_id = OBJECT_ID('dbo.calc_period_metrics'))
BEGIN
  CREATE INDEX IX_calc_period_metrics_emp_id ON dbo.calc_period_metrics (emp_id);
END
GO
