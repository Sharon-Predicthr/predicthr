

/****** Object:  StoredProcedure [dbo].[usp_calc_integrity]    Script Date: 16/11/2025 12:08:56 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[usp_calc_integrity]
  @client_id NVARCHAR(50)
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /* Guard */
  IF NOT EXISTS (SELECT 1 FROM dbo.calculated_data WHERE client_id=@client_id)
  BEGIN
    RAISERROR('No rows in calculated_data for client_id=%s.', 16, 1, @client_id);
    RETURN;
  END

  /* Fresh start */
  DELETE FROM dbo.report_integrity WHERE client_id=@client_id;

  /* Weights & threshold (with defaults) */
  DECLARE
    @w_odd  FLOAT = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='integrity_w_odd') AS FLOAT), 0.5),
    @w_door FLOAT = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='integrity_w_door') AS FLOAT), 0.3),
    @w_ping FLOAT = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='integrity_w_ping') AS FLOAT), 0.2),
    @min_actionable INT = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='integrity_intervention_min_score') AS INT), 10);

  /* Working set from calculated_data */
  IF OBJECT_ID('tempdb..#rows') IS NOT NULL DROP TABLE #rows;
  CREATE TABLE #rows
  (
    client_id NVARCHAR(50), emp_id NVARCHAR(100),
    department NVARCHAR(200), emp_role NVARCHAR(200),

    baseline_start DATE, baseline_end DATE, baseline_days INT,
    recent_start   DATE, recent_end   DATE, recent_days  INT,

    odd_r   FLOAT, door_r FLOAT, ping_r FLOAT,

    risk_score INT, risk_type NVARCHAR(40),
    intervention_id INT NULL, intervention_short NVARCHAR(200) NULL,
    intervention_detail NVARCHAR(2000) NULL, priority INT NULL,
    score_explanation NVARCHAR(600)
  );

  INSERT INTO #rows(client_id,emp_id,department,emp_role,
                    baseline_start,baseline_end,baseline_days,
                    recent_start,recent_end,recent_days,
                    odd_r,door_r,ping_r,
                    risk_score,risk_type,score_explanation)
  SELECT
    cd.client_id, cd.emp_id, cd.department, cd.emp_role,
    cd.baseline_start, cd.baseline_end, cd.baseline_days,
    cd.recent_start,   cd.recent_end,   cd.recent_days,

    ISNULL(cd.odd_pct_r,0),
    ISNULL(cd.door_mis_pct_r,0),
    ISNULL(cd.pingpong_pct_r,0),

    0, N'integrity',
    LEFT(
      N'baseline['
      + CONVERT(NVARCHAR(10), cd.baseline_start, 120) + N'→'
      + CONVERT(NVARCHAR(10), cd.baseline_end,   120)
      + N', workdays='       + CAST(cd.baseline_days AS NVARCHAR(10))
      + N', adj_workdays='   + CAST(cd.baseline_days AS NVARCHAR(10))
      + N', present='        + CAST(cd.pres_b AS NVARCHAR(10))
      + N', pres='           + CONVERT(NVARCHAR(20), ROUND(cd.pres_b_norm, 2)) + N'%] '

      + N'recent['
      + CONVERT(NVARCHAR(10), cd.recent_start, 120) + N'→'
      + CONVERT(NVARCHAR(10), cd.recent_end,   120)
      + N', workdays='       + CAST(cd.recent_days AS NVARCHAR(10))
      + N', adj_workdays='   + CAST(cd.recent_days AS NVARCHAR(10))
      + N', present='        + CAST(cd.pres_r AS NVARCHAR(10))
      + N', pres='           + CONVERT(NVARCHAR(20), ROUND(cd.pres_r_norm, 2)) + N'%] ; '
    , 600)
  FROM dbo.calculated_data cd
  WHERE cd.client_id=@client_id;

  /* Auto-scale: if metrics look like 0..1, scale them to 0..100 before weighting */
  DECLARE @max_component FLOAT;
  SELECT @max_component = MAX(v)
  FROM (
    SELECT MAX(odd_r)  AS v FROM #rows
    UNION ALL SELECT MAX(door_r) FROM #rows
    UNION ALL SELECT MAX(ping_r) FROM #rows
  ) s;

  DECLARE @scale FLOAT = CASE WHEN @max_component IS NULL THEN 1.0
                              WHEN @max_component <= 1.0 THEN 100.0
                              ELSE 1.0 END;

  /* Compute scores */
  UPDATE r
  SET r.risk_score = CAST(ROUND((r.odd_r  * @scale * @w_odd)
                              + (r.door_r * @scale * @w_door)
                              + (r.ping_r * @scale * @w_ping), 0) AS INT),
      r.score_explanation =
        LEFT(
          r.score_explanation
          + N'odd='  + CONVERT(NVARCHAR(20), ROUND(r.odd_r  * @scale, 2)) + N'% ×' + CONVERT(NVARCHAR(10), @w_odd)
          + N'; doors=' + CONVERT(NVARCHAR(20), ROUND(r.door_r * @scale, 2)) + N'% ×' + CONVERT(NVARCHAR(10), @w_door)
          + N'; ping='  + CONVERT(NVARCHAR(20), ROUND(r.ping_r * @scale, 2)) + N'% ×' + CONVERT(NVARCHAR(10), @w_ping)
          + N'; total=' + CONVERT(NVARCHAR(10),
                            CAST(ROUND((r.odd_r  * @scale * @w_odd)
                                     + (r.door_r * @scale * @w_door)
                                     + (r.ping_r * @scale * @w_ping), 0) AS INT)),
          600)
  FROM #rows r;

  /* Interventions (thresholded) */
  DECLARE @iid_default INT=NULL, @short_default NVARCHAR(200)=NULL, @detail_default NVARCHAR(2000)=NULL;

  SELECT TOP 1
    @iid_default = i.intervention_id,
    @short_default = i.short_text,
    @detail_default = i.long_description
  FROM dbo.interventions i
  WHERE i.is_active=1 AND i.short_text LIKE N'%No Intervention Needed%';

  UPDATE r
  SET
    r.intervention_id =
      CASE WHEN r.risk_score < @min_actionable THEN @iid_default
           ELSE (SELECT TOP 1 ri.intervention_id
                 FROM dbo.risk_interventions ri
                 WHERE ri.is_active=1 AND ri.risk_type=N'integrity'
                   AND r.risk_score BETWEEN ri.min_score AND ri.max_score
                 ORDER BY ri.priority ASC, ri.min_score ASC)
      END,
    r.priority =
      CASE WHEN r.risk_score < @min_actionable THEN 99
           ELSE (SELECT TOP 1 ri.priority
                 FROM dbo.risk_interventions ri
                 WHERE ri.is_active=1 AND ri.risk_type=N'integrity'
                   AND r.risk_score BETWEEN ri.min_score AND ri.max_score
                 ORDER BY ri.priority ASC, ri.min_score ASC)
      END
  FROM #rows r;

  UPDATE r
  SET r.intervention_id = ISNULL(r.intervention_id, @iid_default),
      r.priority        = ISNULL(r.priority, 99)
  FROM #rows r;

  UPDATE r
  SET r.intervention_short  = i.short_text,
      r.intervention_detail = i.long_description
  FROM #rows r
  JOIN dbo.interventions i
    ON i.intervention_id = r.intervention_id;

  /* Persist */
  INSERT INTO dbo.report_integrity
  (
    client_id, emp_id, department, emp_role, site_name,
    risk_score, risk_type,
    intervention_id, intervention_short, intervention_detail,
    priority, score_explanation, computed_at
  )
  SELECT
    r.client_id, r.emp_id, r.department, r.emp_role, a.site_name,
    r.risk_score, r.risk_type,
    r.intervention_id, r.intervention_short, r.intervention_detail,
    r.priority, r.score_explanation, SYSUTCDATETIME()
  FROM #rows r
  LEFT JOIN dbo.v_client_emp_site a ON a.client_id = r.client_id AND a.emp_id = r.emp_id;
END
GO

