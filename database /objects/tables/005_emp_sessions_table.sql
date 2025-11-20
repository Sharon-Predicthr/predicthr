SET QUOTED_IDENTIFIER ON;
GO
	
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.emp_sessions') AND type = 'U')
BEGIN
  CREATE TABLE dbo.emp_sessions
  (
    client_id      NVARCHAR(50)  NOT NULL,
    emp_id         NVARCHAR(100) NOT NULL,
    session_start  DATETIME2(0)  NOT NULL,
    session_end    DATETIME2(0)  NOT NULL,
    minutes_worked INT           NOT NULL,
    in_door        NVARCHAR(200) NULL,
    out_door       NVARCHAR(200) NULL,
    any_remote     BIT           NOT NULL DEFAULT(0),
    PRIMARY KEY (client_id, emp_id, session_start)
  );
  CREATE INDEX IX_emp_sessions_client_emp_date
    ON dbo.emp_sessions(client_id, emp_id, session_start)
    INCLUDE(session_end, minutes_worked, in_door, out_door, any_remote);

  CREATE INDEX IX_sessions_client_date_emp
	ON dbo.emp_sessions(client_id, session_start) INCLUDE(emp_id);
END
GO

