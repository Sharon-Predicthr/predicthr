
/****** Object:  StoredProcedure [dbo].[usp_calc_flight]    Script Date: 16/11/2025 12:07:49 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[usp_calc_flight]
  @client_id NVARCHAR(50)
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /* Start clean for this client */
  DELETE FROM dbo.report_flight WHERE client_id=@client_id;

  /* Load weights / thresholds with safe fallbacks */
  DECLARE
    @w_drop FLOAT, @w_short FLOAT, @w_streak FLOAT,
    @scale_min_days INT, @min_actionable INT;

  SELECT
    @w_drop = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_w_drop') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL    AND config_key='flight_w_drop') AS FLOAT), 0.70),
    @w_short = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_w_short') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL    AND config_key='flight_w_short') AS FLOAT), 0.10),
    @w_streak = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_w_streak') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL    AND config_key='flight_w_streak') AS FLOAT), 0.20),
    @scale_min_days = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_scale_min_recent_days') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL    AND config_key='flight_scale_min_recent_days') AS INT), 10),
    @min_actionable = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='flight_intervention_min_score') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL    AND config_key='flight_intervention_min_score') AS INT), 15);

  /* Base rows from calculated_data (carry department/emp_role) */
  IF OBJECT_ID('tempdb..#calc') IS NOT NULL DROP TABLE #calc;
  CREATE TABLE #calc
  (
    client_id NVARCHAR(50),
    emp_id NVARCHAR(100),
    department NVARCHAR(200),
    emp_role NVARCHAR(200),

    baseline_start DATE, baseline_end DATE, baseline_days INT,
    recent_start   DATE, recent_end   DATE, recent_days  INT,

    pres_b_norm FLOAT, pres_r_norm FLOAT,
    pres_b_norm_adj FLOAT, pres_r_norm_adj FLOAT,
    short_gap_count_r INT, short_gap_count_r_adj INT,
    max_off_run INT, max_off_run_adj INT
  );

  INSERT INTO #calc
  SELECT
    cd.client_id, cd.emp_id, cd.department, cd.emp_role,
    cd.baseline_start, cd.baseline_end, cd.baseline_days,
    cd.recent_start,   cd.recent_end,   cd.recent_days,
    cd.pres_b_norm, cd.pres_r_norm,
    cd.pres_b_norm_adj, cd.pres_r_norm_adj,
    cd.short_gap_count_r, cd.short_gap_count_r_adj,
    cd.max_off_run, cd.max_off_run_adj
  FROM dbo.calculated_data cd
  WHERE cd.client_id=@client_id;

  /* Distinct presence days from emp_sessions */
  IF OBJECT_ID('tempdb..#pres') IS NOT NULL DROP TABLE #pres;
  SELECT DISTINCT emp_id, CAST(session_start AS DATE) AS d
  INTO #pres
  FROM dbo.emp_sessions
  WHERE client_id=@client_id;

/*
  /* Legit absences (fully excluded) */
  IF OBJECT_ID('tempdb..#legit') IS NOT NULL DROP TABLE #legit;
  SELECT emp_id, calendar_date AS d
  INTO #legit
  FROM dbo.emp_day_legit
  WHERE client_id=@client_id AND confidence >= 0.6;
*/

  /* Work calendar */
  IF OBJECT_ID('tempdb..#wd') IS NOT NULL DROP TABLE #wd;
  SELECT calendar_date AS d, is_workday
  INTO #wd
  FROM dbo.work_calendar
  WHERE client_id=@client_id;

  /* Numerators/denominators used for final pct */
  IF OBJECT_ID('tempdb..#use_counts') IS NOT NULL DROP TABLE #use_counts;
  CREATE TABLE #use_counts
  (
    emp_id NVARCHAR(100) PRIMARY KEY,
    pres_b_used INT, den_b_raw INT, den_b_adj INT,
    pres_r_used INT, den_r_raw INT, den_r_adj INT
  );

  INSERT INTO #use_counts(emp_id,pres_b_used,den_b_raw,den_b_adj,pres_r_used,den_r_raw,den_r_adj)
  SELECT
    c.emp_id,
    (SELECT COUNT(*) FROM #pres p WHERE p.emp_id=c.emp_id AND p.d BETWEEN c.baseline_start AND c.baseline_end),
    (SELECT COUNT(*) FROM #wd   w WHERE w.is_workday=1 AND w.d BETWEEN c.baseline_start AND c.baseline_end),
    (SELECT COUNT(*) FROM #wd   w WHERE w.is_workday=1 AND w.d BETWEEN c.baseline_start AND c.baseline_end ),
      -- AND NOT EXISTS(SELECT 1 FROM #legit l WHERE l.emp_id=c.emp_id AND l.d=w.d)),
    (SELECT COUNT(*) FROM #pres p WHERE p.emp_id=c.emp_id AND p.d BETWEEN c.recent_start AND c.recent_end),
    (SELECT COUNT(*) FROM #wd   w WHERE w.is_workday=1 AND w.d BETWEEN c.recent_start AND c.recent_end),
    (SELECT COUNT(*) FROM #wd   w WHERE w.is_workday=1 AND w.d BETWEEN c.recent_start AND c.recent_end )
      --  AND NOT EXISTS(SELECT 1 FROM #legit l WHERE l.emp_id=c.emp_id AND l.d=w.d))
  FROM #calc c;

  /* Scores to insert */
  IF OBJECT_ID('tempdb..#score') IS NOT NULL DROP TABLE #score;
  CREATE TABLE #score
  (
    client_id NVARCHAR(50), emp_id NVARCHAR(100),
    department NVARCHAR(200), emp_role NVARCHAR(200),
    risk_score INT, score_explanation NVARCHAR(700),
    risk_type NVARCHAR(40), intervention_id INT,
    intervention_short NVARCHAR(200),
    intervention_detail NVARCHAR(2000),
    priority INT
  );

  DECLARE
    @emp NVARCHAR(100),
    @pb FLOAT, @pr FLOAT, @pbA FLOAT, @prA FLOAT,
    @sg INT, @sgA INT, @mr INT, @mrA INT, @r INT,
    @bS DATE, @bE DATE, @bD INT, @rS DATE, @rE DATE,
    @pres_b_used INT, @den_b_raw INT, @den_b_adj INT,
    @pres_r_used INT, @den_r_raw INT, @den_r_adj INT;

  DECLARE c CURSOR LOCAL FAST_FORWARD FOR
    SELECT c.emp_id,
           c.pres_b_norm, c.pres_r_norm, c.pres_b_norm_adj, c.pres_r_norm_adj,
           c.short_gap_count_r, c.short_gap_count_r_adj, c.max_off_run, c.max_off_run_adj,
           c.recent_days,
           c.baseline_start, c.baseline_end, c.baseline_days, c.recent_start, c.recent_end,
           u.pres_b_used, u.den_b_raw, u.den_b_adj, u.pres_r_used, u.den_r_raw, u.den_r_adj
    FROM #calc c
    JOIN #use_counts u ON u.emp_id=c.emp_id;

  OPEN c;
  FETCH NEXT FROM c INTO
    @emp, @pb, @pr, @pbA, @prA, @sg, @sgA, @mr, @mrA, @r,
    @bS, @bE, @bD, @rS, @rE,
    @pres_b_used, @den_b_raw, @den_b_adj, @pres_r_used, @den_r_raw, @den_r_adj;

  WHILE @@FETCH_STATUS=0
  BEGIN
    DECLARE @use_pb FLOAT = COALESCE(@pbA,@pb);
    DECLARE @use_pr FLOAT = COALESCE(@prA,@pr);
    DECLARE @use_sg INT   = COALESCE(@sgA,@sg);
    DECLARE @use_mr INT   = COALESCE(@mrA,@mr);
    DECLARE @adj BIT      = CASE WHEN @pbA IS NOT NULL OR @prA IS NOT NULL OR @sgA IS NOT NULL OR @mrA IS NOT NULL THEN 1 ELSE 0 END;

    DECLARE @den_b_used INT = CASE WHEN @pbA IS NOT NULL THEN @den_b_adj ELSE @den_b_raw END;
    DECLARE @den_r_used INT = CASE WHEN @prA IS NOT NULL THEN @den_r_adj ELSE @den_r_raw END;

    DECLARE @pct_b FLOAT = CASE WHEN @den_b_used>0 THEN 100.0*@pres_b_used/@den_b_used ELSE 0 END;
    DECLARE @pct_r FLOAT = CASE WHEN @den_r_used>0 THEN 100.0*@pres_r_used/@den_r_used ELSE 0 END;

    DECLARE @drop FLOAT  = CASE WHEN @pct_b>@pct_r THEN @pct_b-@pct_r ELSE 0 END;
    DECLARE @short FLOAT = (@use_sg * 5.0);
    DECLARE @streak FLOAT= CASE WHEN @use_mr >= 3 THEN 10.0 ELSE 0.0 END;

    DECLARE @raw INT = CAST(ROUND((@w_drop*@drop)+(@w_short*@short)+(@w_streak*@streak),0) AS INT);
    DECLARE @scale FLOAT = CASE WHEN @r IS NULL OR @r >= @scale_min_days THEN 1.0
                                WHEN @r <= 0 THEN 0 ELSE @r*1.0/@scale_min_days END;
    DECLARE @final INT = CAST(ROUND(@raw*@scale,0) AS INT);

    DECLARE @ex NVARCHAR(700) =
      N'baseline['
      + CONVERT(NVARCHAR(10),@bS,120) + N'→' + CONVERT(NVARCHAR(10),@bE,120)
      + N', workdays=' + CAST(@bD AS NVARCHAR(10))
      + N', adj_workdays=' + CAST(@den_b_used AS NVARCHAR(10))
      + N', present=' + CAST(@pres_b_used AS NVARCHAR(10))
      + N', pres=' + CAST(CAST(@pct_b AS DECIMAL(10,2)) AS NVARCHAR(10)) + N'%] '
      + N'recent['
      + CONVERT(NVARCHAR(10),@rS,120) + N'→' + CONVERT(NVARCHAR(10),@rE,120)
      + N', workdays=' + CAST(@r AS NVARCHAR(10))
      + N', adj_workdays=' + CAST(@den_r_used AS NVARCHAR(10))
      + N', present=' + CAST(@pres_r_used AS NVARCHAR(10))
      + N', pres=' + CAST(CAST(@pct_r AS DECIMAL(10,2)) AS NVARCHAR(10)) + N'%]'
      + N'; drop=' + CAST(CAST(@drop AS DECIMAL(10,2)) AS NVARCHAR(10))
      + N'; short_gaps=' + CAST(@use_sg AS NVARCHAR(10))
      + N'; streak=' + CAST(@use_mr AS NVARCHAR(10))
      + N'; scaled=' + CAST(@raw AS NVARCHAR(10)) + N'×' + CAST(@scale AS NVARCHAR(10))
      + N'; adj=' + CASE WHEN @adj=1 THEN N'Y' ELSE N'N' END;

    /* Intervention mapping */
    DECLARE @iid INT=NULL, @short_txt NVARCHAR(200)=NULL, @detail NVARCHAR(2000)=NULL, @prio INT=NULL, @rtype NVARCHAR(40)=N'flight';

    IF @final < @min_actionable
    BEGIN
      SELECT TOP 1 @iid = i.intervention_id, @short_txt=i.short_text, @detail=i.long_description
      FROM dbo.interventions i
      WHERE i.is_active=1 AND i.short_text LIKE N'%No Intervention Needed%';
      IF @iid IS NULL
      BEGIN
        SELECT TOP 1 @iid=i.intervention_id, @short_txt=i.short_text, @detail=i.long_description
        FROM dbo.interventions i WHERE i.is_active=1 ORDER BY i.intervention_id ASC;
      END
      SET @prio = 99;
    END
    ELSE
    BEGIN
      SELECT TOP 1 @iid=ri.intervention_id, @prio=ri.priority
      FROM dbo.risk_interventions ri
      WHERE ri.is_active=1 AND ri.risk_type=@rtype AND @final BETWEEN ri.min_score AND ri.max_score
      ORDER BY ri.priority ASC, ri.min_score ASC;

      IF @iid IS NULL
        SELECT TOP 1 @iid=i.intervention_id FROM dbo.interventions i WHERE i.is_active=1 AND i.short_text LIKE N'%No Intervention Needed%';

      SELECT @short_txt=i.short_text, @detail=i.long_description
      FROM dbo.interventions i WHERE i.intervention_id=@iid;
    END

    INSERT INTO dbo.report_flight
      (client_id,emp_id,department,emp_role,site_name,risk_score,risk_type,intervention_id,intervention_short,intervention_detail,priority,score_explanation,computed_at)
    SELECT @client_id,@emp,c.department,c.emp_role,a.site_name,@final,@rtype,@iid,@short_txt,@detail,COALESCE(@prio,99),@ex,SYSUTCDATETIME()
    FROM #calc c 
	LEFT JOIN dbo.v_client_emp_site a ON a.client_id = @client_id AND a.emp_id = @emp
	WHERE c.emp_id=@emp;

    FETCH NEXT FROM c INTO
      @emp, @pb, @pr, @pbA, @prA, @sg, @sgA, @mr, @mrA, @r,
      @bS, @bE, @bD, @rS, @rE,
      @pres_b_used, @den_b_raw, @den_b_adj, @pres_r_used, @den_r_raw, @den_r_adj;
  END
  CLOSE c; DEALLOCATE c;
END
GO

