

/****** Object:  StoredProcedure [dbo].[usp_update_adjusted_metrics]    Script Date: 16/11/2025 12:12:09 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


IF OBJECT_ID('dbo.usp_update_adjusted_metrics', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_update_adjusted_metrics;
GO


CREATE OR ALTER PROCEDURE [dbo].[usp_update_adjusted_metrics]
  @client_id NVARCHAR(50),
  @confidence_threshold FLOAT = NULL   -- optional, unused if no legit_absences table
AS
BEGIN
  SET NOCOUNT ON;

  IF NOT EXISTS (SELECT 1 FROM dbo.calculated_data WHERE client_id=@client_id)
  BEGIN
    RAISERROR('No rows in calculated_data for client_id=%s.', 16, 1, @client_id);
    RETURN;
  END

  ---------------------------------------------------------------------------
  -- 1) Pull windows + stored presence
  ---------------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#win') IS NOT NULL DROP TABLE #win;
  CREATE TABLE #win(
    emp_id NVARCHAR(100) PRIMARY KEY,
    b_start DATE, b_end DATE,
    r_start DATE, r_end DATE,
    pres_b INT, pres_r INT
  );

  INSERT INTO #win(emp_id,b_start,b_end,r_start,r_end,pres_b,pres_r)
  SELECT emp_id, baseline_start, baseline_end, recent_start, recent_end, pres_b, pres_r
  FROM dbo.calculated_data
  WHERE client_id=@client_id;

  ---------------------------------------------------------------------------
  -- 2) Denominators from emp_work_calendar (authoritative)
  ---------------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#den') IS NOT NULL DROP TABLE #den;
  CREATE TABLE #den(
    emp_id NVARCHAR(100) PRIMARY KEY,
    denom_b INT NULL,
    denom_r INT NULL
  );

  INSERT INTO #den(emp_id,denom_b)
  SELECT w.emp_id, COUNT(*) AS denom_b
  FROM #win w
  JOIN dbo.emp_work_calendar ewc
       ON ewc.client_id=@client_id
      AND ewc.emp_id = w.emp_id
      AND ewc.is_working = 1
      AND ewc.calendar_date BETWEEN w.b_start AND w.b_end
  GROUP BY w.emp_id;

  UPDATE d
     SET d.denom_r = x.cnt
  FROM #den d
  JOIN (
    SELECT w.emp_id, COUNT(*) AS cnt
    FROM #win w
    JOIN dbo.emp_work_calendar ewc
         ON ewc.client_id=@client_id
        AND ewc.emp_id = w.emp_id
        AND ewc.is_working = 1
        AND ewc.calendar_date BETWEEN w.r_start AND w.r_end
    GROUP BY w.emp_id
  ) x ON x.emp_id = d.emp_id;

  -- Make sure every employee has a row
  INSERT INTO #den(emp_id,denom_b,denom_r)
  SELECT w.emp_id, 0, 0
  FROM #win w
  WHERE NOT EXISTS (SELECT 1 FROM #den d WHERE d.emp_id=w.emp_id);

  UPDATE #den SET denom_b = ISNULL(denom_b,0), denom_r = ISNULL(denom_r,0);

  ---------------------------------------------------------------------------
  -- 3) (Optional) subtract legit_absences from denominators when table exists
  --     NOTE: kept simple; if table does not exist, this step is skipped.
  ---------------------------------------------------------------------------
  IF OBJECT_ID('dbo.legit_absences','U') IS NOT NULL
  BEGIN
    DECLARE @thr FLOAT = COALESCE(@confidence_threshold, 0.60);

    UPDATE d
       SET d.denom_b = CASE WHEN z.sub_b IS NULL THEN d.denom_b
                            ELSE CASE WHEN d.denom_b - z.sub_b < 0 THEN 0 ELSE d.denom_b - z.sub_b END END
    FROM #den d
    LEFT JOIN (
      SELECT la.emp_id, COUNT(*) AS sub_b
      FROM dbo.legit_absences la
      JOIN #win w ON w.emp_id = la.emp_id
      WHERE la.client_id=@client_id
        AND la.confidence >= @thr
        AND la.absence_date BETWEEN w.b_start AND w.b_end
      GROUP BY la.emp_id
    ) z ON z.emp_id = d.emp_id;

    UPDATE d
       SET d.denom_r = CASE WHEN z.sub_r IS NULL THEN d.denom_r
                            ELSE CASE WHEN d.denom_r - z.sub_r < 0 THEN 0 ELSE d.denom_r - z.sub_r END END
    FROM #den d
    LEFT JOIN (
      SELECT la.emp_id, COUNT(*) AS sub_r
      FROM dbo.legit_absences la
      JOIN #win w ON w.emp_id = la.emp_id
      WHERE la.client_id=@client_id
        AND la.confidence >= @thr
        AND la.absence_date BETWEEN w.r_start AND w.r_end
      GROUP BY la.emp_id
    ) z ON z.emp_id = d.emp_id;
  END

  ---------------------------------------------------------------------------
  -- 4) Update normalized presence in calculated_data
  ---------------------------------------------------------------------------
  UPDATE c
     SET c.pres_b_norm = CASE WHEN d.denom_b>0 THEN 100.0 * ISNULL(w.pres_b,0) / d.denom_b ELSE 0 END,
         c.pres_r_norm = CASE WHEN d.denom_r>0 THEN 100.0 * ISNULL(w.pres_r,0) / d.denom_r ELSE 0 END
  FROM dbo.calculated_data c
  JOIN #win w ON w.emp_id = c.emp_id
  JOIN #den d ON d.emp_id = c.emp_id
  WHERE c.client_id=@client_id;
END
GO

