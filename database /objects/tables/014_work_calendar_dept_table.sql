IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.work_calendar_dept') AND type = 'U')
BEGIN

SET QUOTED_IDENTIFIER ON;
GO
  
CREATE TABLE dbo.work_calendar_dept
(
  client_id         NVARCHAR(50) NOT NULL,
  calendar_date     DATE         NOT NULL,
  department        NVARCHAR(200) NOT NULL,
  dept_present      INT          NOT NULL,
  dept_active       INT          NOT NULL,
  dept_coverage_pct FLOAT        NOT NULL,
  is_workday_dept   BIT          NOT NULL,
  computed_at       DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
  PRIMARY KEY (client_id, calendar_date, department)
);
  CREATE INDEX IX_work_calendar_dept_client_calendar_department
    ON dbo.work_calendar_dept(client_id, calendar_date, department)
    INCLUDE(dept_present, dept_active, dept_coverage_pct, is_workday_dept);




END
