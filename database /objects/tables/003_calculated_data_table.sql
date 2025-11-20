SET QUOTED_IDENTIFIER ON;
GO
  
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID('dbo.calculated_data') AND type = 'U')
BEGIN
  CREATE TABLE dbo.calculated_data
  (
    client_id        NVARCHAR(50)  NOT NULL,
    emp_id           NVARCHAR(100) NOT NULL,
    department       NVARCHAR(200) ,
    emp_role         NVARCHAR(200) ,
    site_name        NVARCHAR(200) ,

    baseline_start   DATE          NOT NULL,
    baseline_end     DATE          NOT NULL,
    baseline_days    INT           NOT NULL,
    recent_start     DATE          NOT NULL,
    recent_end       DATE          NOT NULL,
    recent_days      INT          NOT NULL,

    pres_b           INT           NOT NULL,
    pres_r           INT           NOT NULL,
    pres_b_norm      FLOAT         NOT NULL,
    pres_r_norm      FLOAT         NOT NULL,

    max_off_run       INT          NOT NULL,
    short_gap_count_r INT          NOT NULL,

    long_r            FLOAT        NOT NULL,
    late_r            FLOAT        NOT NULL,
    avg_min_b         FLOAT        NULL,
    avg_min_r         FLOAT        NULL,

    odd_pct_r         FLOAT        NOT NULL,
    door_mis_pct_r    FLOAT        NOT NULL,
    pingpong_pct_r    FLOAT        NOT NULL,

    /* >>> NEW: static aliases the reports expect (no SP changes needed) */
    odd_pct_recent              AS (odd_pct_r) PERSISTED,
    door_mismatch_pct_recent   AS (door_mis_pct_r) PERSISTED,
    pingpong_pct_recent        AS (pingpong_pct_r) PERSISTED,

    pres_b_norm_adj       FLOAT  NULL,
    pres_r_norm_adj       FLOAT  NULL,
    max_off_run_adj       INT    NULL,
    short_gap_count_r_adj INT    NULL,
    legit_abs_days_b      INT    NULL,
    legit_abs_days_r      INT    NULL,
    legit_abs_conf_avg_r  FLOAT  NULL,  -- 0..1 average confidence on recent legit days

    CONSTRAINT PK_calculated_data PRIMARY KEY (client_id, emp_id)
  );
  CREATE UNIQUE INDEX UX_calculated_data_client_emp
    ON dbo.calculated_data(client_id, emp_id);
END
GO

