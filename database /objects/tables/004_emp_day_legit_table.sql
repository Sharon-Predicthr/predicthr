SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.emp_day_legit') AND type = 'U')
BEGIN
CREATE TABLE dbo.emp_day_legit
(
  client_id        NVARCHAR(50)  NOT NULL,
  emp_id           NVARCHAR(100) NOT NULL,
  calendar_date    DATE          NOT NULL,
  is_legit_absent  BIT           NOT NULL,   -- 1=legit block day (exclude/discount from penalties)
  inferred_reason  NVARCHAR(32)  NOT NULL,   -- 'vacation_like' | 'sick_like' | 'dept_off' | 'org_off' | 'partial_errand'
  confidence       FLOAT         NOT NULL,   -- 0..1
  source_note      NVARCHAR(100) NULL,       -- short detail (e.g., 'anchored_weekend', 'dept_coverage_14%')
  created_at       DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
  PRIMARY KEY (client_id, emp_id, calendar_date)
);
  CREATE INDEX IX_emp_day_legit_client_emp_calendar
    ON dbo.emp_day_legit(client_id, emp_id, calendar_date);

  CREATE INDEX IX_legit_date_emp
	ON dbo.emp_day_legit(client_id, calendar_date, emp_id);
END
GO

