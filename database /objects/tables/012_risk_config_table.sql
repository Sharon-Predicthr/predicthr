IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.risk_config') AND type = 'U')
BEGIN
SET QUOTED_IDENTIFIER ON;
GO
  CREATE TABLE dbo.risk_config
  (
    client_id    NVARCHAR(50)  NULL,
    config_key   NVARCHAR(100) NOT NULL,
    config_value NVARCHAR(400) NOT NULL
  );
  CREATE UNIQUE INDEX UX_risk_config_client_key
    ON dbo.risk_config(client_id, config_key);


END
