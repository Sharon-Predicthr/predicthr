SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.absence') AND type = 'U')
BEGIN 
CREATE TABLE dbo.absence
(
  client_id            NVARCHAR(50)   NOT NULL,
  emp_id               NVARCHAR(100)  NOT NULL,
  from_date            DATETIME       NOT NULL,
  to_date              DATETIME       NOT NULL,
  client_absence_code  SMALLINT       NOT NULL, 
  site_name            NVARCHAR(200)  NULL,
  department           NVARCHAR(200)  NOT NULL DEFAULT(N'Not Reported')
);

CREATE INDEX IX_absence_client_emp_date
  ON dbo.absence(client_id, emp_id, from_date)
  INCLUDE( to_date );

CREATE INDEX IX_absence_client_date_dept
  ON dbo.absence(client_id, from_date)
  INCLUDE(emp_id, department);
END
GO
