IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.attendance_rejects') AND type = 'U')
BEGIN

  CREATE TABLE dbo.attendance_rejects
  (
    client_id  NVARCHAR(50)  NOT NULL,
    raw_line   NVARCHAR(MAX) NOT NULL,
    reason     NVARCHAR(400) NOT NULL,
    created_at DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
  );


END