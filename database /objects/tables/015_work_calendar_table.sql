IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.work_calendar') AND type = 'U')
BEGIN
SET QUOTED_IDENTIFIER ON;
GO
  CREATE TABLE dbo.work_calendar
  (
    client_id        NVARCHAR(50) NOT NULL,
    calendar_date    DATE         NOT NULL,
    is_workday       BIT          NOT NULL,
    present_emp      INT          NOT NULL,
    active_emp       INT          NOT NULL,
    coverage_pct     FLOAT        NOT NULL,
    detection_method NVARCHAR(50) NOT NULL,
    computed_at      DATETIME2(0) NOT NULL,
    day_of_week      NVARCHAR(20) NOT NULL,
    PRIMARY KEY (client_id, calendar_date)
  );
  CREATE INDEX IX_work_calendar_client_date
	ON dbo.work_calendar(client_id, calendar_date) ;


END
