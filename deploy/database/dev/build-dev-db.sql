-- build-dev-db.sql
-- Rebuilds full DB for DEV

PRINT 'Building PredictHR_DB (DEV)...';
GO
    
:r build-common.sql
:r apply-migrations.sql
GO

