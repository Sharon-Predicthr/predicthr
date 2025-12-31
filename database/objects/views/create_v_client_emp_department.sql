
/****** Object:  View [dbo].[v_client_emp_department]    Script Date: 16/11/2025 12:24:14 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.v_client_emp_department', 'V') IS NOT NULL
    DROP VIEW dbo.v_client_emp_department;
GO

CREATE OR ALTER   VIEW [dbo].[v_client_emp_department] AS
SELECT client_id, emp_id, MIN(department) AS department
FROM dbo.attendance
WHERE department IS NOT NULL
GROUP BY client_id, emp_id
GO
