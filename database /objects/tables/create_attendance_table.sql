IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.attendance') AND type = 'U')
BEGIN

CREATE TABLE dbo.attendance
(
  client_id   NVARCHAR(50)  NOT NULL,
  emp_id      NVARCHAR(100) NOT NULL,
  event_date  DATE          NOT NULL,
  event_time  TIME(0)       NOT NULL,
  site_name   NVARCHAR(200)  NULL,
  department  NVARCHAR(200) NOT NULL DEFAULT(N'Not Reported'),
  emp_role    NVARCHAR(200) NOT NULL DEFAULT(N'Not Reported'),
  badge_id    NVARCHAR(200) NULL,
  door_id     NVARCHAR(200) NULL
);

CREATE INDEX IX_attendance_client_emp_date
  ON dbo.attendance(client_id, emp_id, event_date)
  INCLUDE(event_time, door_id);

CREATE INDEX IX_attendance_client_date_dept
  ON dbo.attendance(client_id, event_date)
  INCLUDE(emp_id, department);

END