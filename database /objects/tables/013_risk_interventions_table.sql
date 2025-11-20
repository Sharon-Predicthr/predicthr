SET QUOTED_IDENTIFIER ON;
GO
  
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.risk_interventions') AND type = 'U')
BEGIN
  
  CREATE TABLE dbo.risk_interventions
  (
    risk_type       NVARCHAR(40)  NOT NULL,  /* 'flight' | 'integrity' | 'workload' */
    min_score       INT           NOT NULL,
    max_score       INT           NOT NULL,
    intervention_id INT           NOT NULL,
    priority        INT           NOT NULL DEFAULT(1),
    is_active       BIT           NOT NULL DEFAULT(1)
  );
  CREATE INDEX IX_risk_interventions_risk_range
    ON dbo.risk_interventions(risk_type, min_score, max_score, priority)
    INCLUDE(intervention_id, is_active);
END

GO

