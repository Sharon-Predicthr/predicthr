IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.legit_abs_blocks') AND type = 'U')
BEGIN
CREATE TABLE dbo.legit_abs_blocks
(
  client_id        NVARCHAR(50)  NOT NULL,
  emp_id           NVARCHAR(100) NOT NULL,
  block_start      DATE          NOT NULL,
  block_end        DATE          NOT NULL,
  block_days       INT           NOT NULL,
  inferred_reason  NVARCHAR(32)  NOT NULL,   -- 'vacation_like' | 'sick_like' | ...
  confidence       FLOAT         NOT NULL,   -- 0..1
  dept_support_pct FLOAT         NULL,       -- optional cohort support within department
  is_full_exclude  BIT           NOT NULL,   -- 1=fully exclude days from penalties
  created_at       DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
  PRIMARY KEY (client_id, emp_id, block_start)
);
  CREATE INDEX IX_legit_abs_blocks_client_emp_block_start
    ON dbo.legit_abs_blocks(client_id, emp_id, block_start);

END