

/****** Object:  View [dbo].[v_client_emp_role]    Script Date: 16/11/2025 12:31:57 ******/
DROP VIEW [dbo].[v_client_emp_role]
GO

/****** Object:  View [dbo].[v_client_emp_role]    Script Date: 16/11/2025 12:31:57 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   VIEW [dbo].[v_client_emp_role] AS
SELECT client_id, emp_id, MIN(emp_role) AS emp_role
FROM dbo.attendance
GROUP BY client_id, emp_id, emp_role
GO

