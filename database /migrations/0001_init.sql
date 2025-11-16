IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.MigrationHistory') AND type = 'U')
BEGIN
CREATE TABLE MigrationHistory (
    Id INT IDENTITY PRIMARY KEY,
    Version NVARCHAR(255) NOT NULL,
    AppliedAt DATETIME NOT NULL DEFAULT GETDATE()
);
END
