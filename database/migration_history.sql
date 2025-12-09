-- migration_history.sql
-- This table tracks all applied migrations and prevents re-applying them.

IF OBJECT_ID(N'dbo.MigrationHistory', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.MigrationHistory (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        MigrationName NVARCHAR(255) NOT NULL UNIQUE,
        Checksum NVARCHAR(64) NULL,
        AppliedBy NVARCHAR(255) NULL,
        AppliedOn DATETIME DEFAULT GETDATE()
    );
END;
GO
