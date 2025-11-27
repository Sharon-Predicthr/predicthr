SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.client_absence_type') AND type = 'U')
BEGIN 
CREATE TABLE dbo.client_absence_type
(
  client_id            NVARCHAR(50)   NOT NULL,
  client_absence_code  SMALLINT       NOT NULL,
  descrption           NVARCHAR(500)  NULL,
  absence_code         SMALLINT       NOT NULL
);


END
GO