SET QUOTED_IDENTIFIER ON;
GO
  
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.emp_work_calendar') AND type = 'U')
BEGIN

  CREATE TABLE dbo.emp_work_calendar
  (
    client_id      NVARCHAR(50)   NOT NULL,
    emp_id         NVARCHAR(100)  NOT NULL,
    calendar_date  DATE           NOT NULL,
    is_working     BIT            NOT NULL,   -- 1 = expected to work that day, 0 = not expected
    source_reason  NVARCHAR(80)   NULL,       -- e.g., 'baseline_weekday_pattern','recent_presence','company_off','legit_absence','pre_first_seen','post_last_seen'
    computed_at    DATETIME2(0)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_emp_work_calendar PRIMARY KEY (client_id, emp_id, calendar_date)
  );

  CREATE INDEX IX_emp_work_calendar_emp ON dbo.emp_work_calendar(emp_id, calendar_date);
END

GO

