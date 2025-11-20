IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.interventions') AND type = 'U')
BEGIN
SET QUOTED_IDENTIFIER ON;
GO
  CREATE TABLE dbo.interventions
  (
    intervention_id  INT IDENTITY(1,1) PRIMARY KEY,
    short_text       NVARCHAR(200)  NOT NULL,
    long_description NVARCHAR(2000) NOT NULL,
    is_active        BIT            NOT NULL DEFAULT(1)
  );


END
