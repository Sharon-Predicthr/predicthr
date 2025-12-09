SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.absence_type') AND type = 'U')
BEGIN 
CREATE TABLE dbo.absence_type
(
  absence_code         SMALLINT       NOT NULL,
  descrption           NVARCHAR(500)  NULL
);


END
GO
