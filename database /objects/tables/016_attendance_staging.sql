IF OBJECT_ID('dbo.attendance_staging', 'U') IS NOT NULL
    DROP TABLE dbo.attendance_staging;
GO

CREATE TABLE dbo.attendance_staging (
    batch_id   UNIQUEIDENTIFIER NOT NULL,
    client_id  NVARCHAR(50)     NOT NULL,

    -- עותק 1:1 של העמודות מה־CSV (כמו #raw)
    t1 NVARCHAR(2000) NULL,
    t2 NVARCHAR(2000) NULL,
    t3 NVARCHAR(2000) NULL,
    t4 NVARCHAR(2000) NULL,
    t5 NVARCHAR(2000) NULL,
    t6 NVARCHAR(2000) NULL,
    t7 NVARCHAR(2000) NULL,
    t8 NVARCHAR(2000) NULL,
    t9 NVARCHAR(2000) NULL,

    row_number BIGINT IDENTITY(1,1) NOT NULL,
    CONSTRAINT PK_attendance_staging PRIMARY KEY (batch_id, row_number)
);
GO

CREATE INDEX IX_attendance_staging_client
    ON dbo.attendance_staging(client_id, batch_id);
GO
