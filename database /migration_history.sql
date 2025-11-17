IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'migration_history')
BEGIN
    CREATE TABLE migration_history (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        MigrationName NVARCHAR(255),
        AppliedOn DATETIME DEFAULT GETDATE()
    );
END;
