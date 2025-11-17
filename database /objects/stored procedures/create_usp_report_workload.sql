

/****** Object:  StoredProcedure [dbo].[usp_report_workload]    Script Date: 16/11/2025 12:11:26 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


IF OBJECT_ID('dbo.usp_report_workload', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_report_workload;
GO


CREATE OR ALTER PROCEDURE [dbo].[usp_report_workload]
  @client_id NVARCHAR(50)
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  IF NOT EXISTS (SELECT 1 FROM dbo.calculated_data WHERE client_id=@client_id)
  BEGIN
    RAISERROR('No rows in calculated_data for client_id=%s.', 16, 1, @client_id);
    RETURN;
  END

  /* Clean old rows */
  DELETE FROM dbo.report_workload WHERE client_id=@client_id;

  /* Weights & thresholds */
  DECLARE
    @w_long FLOAT = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='workload_w_long') AS FLOAT), 0.6),
    @w_late FLOAT = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='workload_w_late') AS FLOAT), 0.4),
    @w_bonus FLOAT = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='workload_w_bonus') AS FLOAT), 0.0),
    @min_actionable INT = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='workload_intervention_min_score') AS INT), 10);

  /* Working set */
  IF OBJECT_ID('tempdb..#w') IS NOT NULL DROP TABLE #w;
  CREATE TABLE #w
  (
    client_id NVARCHAR(50), emp_id NVARCHAR(100),
    department NVARCHAR(200), emp_role NVARCHAR(200),

    baseline_start DATE, baseline_end DATE, baseline_days INT,
    recent_start   DATE, recent_end   DATE, recent_days  INT,

    long_r FLOAT, late_r FLOAT,
    avg_min_b FLOAT, avg_min_r FLOAT,

    risk_score INT, risk_type NVARCHAR(40),
    intervention_id INT NULL, intervention_short NVARCHAR(200) NULL,
    intervention_detail NVARCHAR(2000) NULL, priority INT NULL,
    score_explanation NVARCHAR(600)
  );

  INSERT INTO #w(client_id,emp_id,department,emp_role,
                 baseline_start,baseline_end,baseline_days,
                 recent_start,recent_end,recent_days,
                 long_r,late_r,avg_min_b,avg_min_r,
                 risk_score,risk_type,score_explanation)
  SELECT
    cd.client_id, cd.emp_id, cd.department, cd.emp_role,
    cd.baseline_start, cd.baseline_end, cd.baseline_days,
    cd.recent_start,   cd.recent_end,   cd.recent_days,
    ISNULL(cd.long_r,0), ISNULL(cd.late_r,0),
    cd.avg_min_b, cd.avg_min_r,
    0, N'workload',
    LEFT(
      N'baseline['
      + CONVERT(NVARCHAR(10), cd.baseline_start, 120) + N'→'
      + CONVERT(NVARCHAR(10), cd.baseline_end,   120)
      + N', workdays='       + CAST(cd.baseline_days AS NVARCHAR(10))
      + N'] '

      + N'recent['
      + CONVERT(NVARCHAR(10), cd.recent_start, 120) + N'→'
      + CONVERT(NVARCHAR(10), cd.recent_end,   120)
      + N', workdays='       + CAST(cd.recent_days AS NVARCHAR(10))
      + N'] ; '
    , 600)
  FROM dbo.calculated_data cd
  WHERE cd.client_id=@client_id;

  /* Auto-scale for long/late (0..1 or 0..100) */
  DECLARE @max_ll FLOAT;
  SELECT @max_ll = MAX(v)
  FROM (
    SELECT MAX(long_r) AS v FROM #w
    UNION ALL SELECT MAX(late_r) FROM #w
  ) s;

  DECLARE @scale FLOAT = CASE WHEN @max_ll IS NULL THEN 1.0
                              WHEN @max_ll <= 1.0 THEN 100.0
                              ELSE 1.0 END;

  /* Compute Δavg bonus (optional, percent change if present) */
  UPDATE #w
  SET score_explanation =
        LEFT(score_explanation
             + N'long=' + CONVERT(NVARCHAR(20), ROUND(long_r*@scale, 2)) + N'% ×' + CONVERT(NVARCHAR(10), @w_long)
             + N'; late=' + CONVERT(NVARCHAR(20), ROUND(late_r*@scale, 2)) + N'% ×' + CONVERT(NVARCHAR(10), @w_late)
             + CASE WHEN avg_min_b IS NOT NULL AND avg_min_r IS NOT NULL AND @w_bonus <> 0.0
                    THEN N'; Δavg=' + CONVERT(NVARCHAR(20),
                                      ROUND(CASE WHEN avg_min_b > 0 THEN ( (avg_min_r - avg_min_b) * 100.0 / avg_min_b )
                                                 ELSE 0 END, 2)) + N'% ×' + CONVERT(NVARCHAR(10), @w_bonus)
                    ELSE N'; Δavg=0% → bonus=0'
               END
            , 600),
      risk_score =
        CAST(ROUND( (long_r*@scale*@w_long) + (late_r*@scale*@w_late)
                    + CASE WHEN avg_min_b IS NOT NULL AND avg_min_r IS NOT NULL AND @w_bonus <> 0.0 AND avg_min_b > 0
                           THEN (( (avg_min_r - avg_min_b) * 100.0 / avg_min_b ) * @w_bonus)
                           ELSE 0 END
        , 0) AS INT);

  /* Interventions */
  DECLARE @iid_default INT=NULL, @short_default NVARCHAR(200)=NULL, @detail_default NVARCHAR(2000)=NULL;
  SELECT TOP 1
    @iid_default = i.intervention_id,
    @short_default = i.short_text,
    @detail_default = i.long_description
  FROM dbo.interventions i
  WHERE i.is_active=1 AND i.short_text LIKE N'%No Intervention Needed%';

  UPDATE w
  SET
    w.intervention_id =
      CASE WHEN w.risk_score < @min_actionable THEN @iid_default
           ELSE (SELECT TOP 1 ri.intervention_id
                 FROM dbo.risk_interventions ri
                 WHERE ri.is_active=1 AND ri.risk_type=N'workload'
                   AND w.risk_score BETWEEN ri.min_score AND ri.max_score
                 ORDER BY ri.priority ASC, ri.min_score ASC)
      END,
    w.priority =
      CASE WHEN w.risk_score < @min_actionable THEN 99
           ELSE (SELECT TOP 1 ri.priority
                 FROM dbo.risk_interventions ri
                 WHERE ri.is_active=1 AND ri.risk_type=N'workload'
                   AND w.risk_score BETWEEN ri.min_score AND ri.max_score
                 ORDER BY ri.priority ASC, ri.min_score ASC)
      END
  FROM #w w;

  UPDATE w
  SET w.intervention_id = ISNULL(w.intervention_id, @iid_default),
      w.priority        = ISNULL(w.priority, 99)
  FROM #w w;

  UPDATE w
  SET w.intervention_short  = i.short_text,
      w.intervention_detail = i.long_description
  FROM #w w
  JOIN dbo.interventions i
    ON i.intervention_id = w.intervention_id;

  /* Persist */
  INSERT INTO dbo.report_workload
  (
    client_id, emp_id, department, emp_role, site_name,
    risk_score, risk_type,
    intervention_id, intervention_short, intervention_detail,
    priority, score_explanation, computed_at
  )
  SELECT
    w.client_id, w.emp_id, w.department, w.emp_role, a.site_name,
    w.risk_score, w.risk_type,
    w.intervention_id, w.intervention_short, w.intervention_detail,
    w.priority, w.score_explanation, SYSUTCDATETIME()
  FROM #w w
  LEFT join dbo.v_client_emp_site a ON a.client_id = w.client_id AND a.emp_id = w.emp_id;
END
GO

