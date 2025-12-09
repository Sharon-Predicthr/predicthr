

/****** Object:  StoredProcedure [dbo].[usp_report_window]    Script Date: 16/11/2025 12:10:34 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER PROCEDURE [dbo].[usp_report_window]
  @client_id NVARCHAR(50)
AS
BEGIN
  SET NOCOUNT ON;
  SELECT 'Window' AS report_name,
         a.client_id, 
		 a.emp_id, 
		 a.department, 
		 a.emp_role, 
		 b.site_name,
         a.baseline_start, 
		 a.baseline_end, 
		 a.baseline_days,
         a.recent_start, 
		 a.recent_end, 
		 a.recent_days
  FROM	 dbo.calculated_data a
  LEFT JOIN v_client_emp_site b ON a.client_id = b.client_id AND a.emp_id = b.emp_id
  WHERE a.client_id=@client_id
  ORDER BY a.emp_id;
END
GO

