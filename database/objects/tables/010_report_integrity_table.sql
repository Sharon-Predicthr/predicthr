SET QUOTED_IDENTIFIER ON;
GO
	
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.report_fraud') AND type = 'U')
BEGIN

  CREATE TABLE dbo.report_fraud
  (
    client_id           NVARCHAR(50)  NOT NULL,
    emp_id              NVARCHAR(100) NOT NULL,
    department          NVARCHAR(200) NOT NULL,
    emp_role            NVARCHAR(200) NOT NULL,
	site_name			NVARCHAR(200) NOT NULL,
    risk_score          INT           NOT NULL,
    risk_type           NVARCHAR(40)  NOT NULL,
    intervention_id     INT           NULL,
    intervention_short  NVARCHAR(200) NULL,
    intervention_detail NVARCHAR(2000) NULL,
    priority            INT           NULL,
    score_explanation   NVARCHAR(600) NOT NULL,
    computed_at         DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME()
  );
  CREATE INDEX IX_report_fraud_client_score
    ON dbo.report_fraud(client_id, risk_score DESC, emp_id);
END

GO

