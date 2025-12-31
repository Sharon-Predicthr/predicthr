
/****** Object:  View [dbo].[v_client_emp_role]    Script Date: 16/11/2025 12:31:57 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.v_client_emp_role', 'V') IS NOT NULL
    DROP VIEW dbo.v_client_emp_role;
GO

CREATE OR ALTER   VIEW [dbo].[v_client_emp_role] AS
SELECT client_id, emp_id, MIN(emp_role) AS emp_role
FROM dbo.attendance
WHERE emp_role IS NOT NULL
GROUP BY client_id, emp_id
GO

