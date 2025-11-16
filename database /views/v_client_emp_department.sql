
/****** Object:  View [dbo].[v_client_emp_department]    Script Date: 16/11/2025 12:24:14 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER   VIEW [dbo].[v_client_emp_department] AS
SELECT client_id, emp_id, MIN(department) AS department
FROM dbo.attendance
GROUP BY client_id, emp_id, department
GO

