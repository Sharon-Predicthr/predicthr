
/****** Object:  StoredProcedure [dbo].[usp_report_sessions]    Script Date: 16/11/2025 12:09:41 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_report_sessions]
  @client_id NVARCHAR(50)
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
    'Sessions' AS report_name,
    s.client_id,
    CAST(s.session_start AS DATE) AS work_day,     -- computed (replaces missing column)
    s.emp_id,
	vd.department,
	vr.emp_role,
	vs.site_name,
    s.session_start,
    s.session_end,
    s.minutes_worked,
    s.in_door,
    s.out_door,
    s.any_remote
  FROM dbo.emp_sessions s
  LEFT JOIN dbo.v_client_emp_site vs ON vs.client_id = s.client_id AND vs.emp_id = s.emp_id
  LEFT JOIN dbo.v_client_emp_department vd ON vd.client_id = s.client_id AND vd.emp_id = s.emp_id
  LEFT JOIN dbo.v_client_emp_role vr ON vr.client_id = s.client_id AND vr.emp_id = s.emp_id
  WHERE s.client_id = @client_id
  ORDER BY s.emp_id,
           CAST(s.session_start AS DATE),
           s.session_start;
END
GO

