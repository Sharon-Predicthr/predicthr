
/****** Object:  View [dbo].[v_client_emp_site]    Script Date: 16/11/2025 12:32:36 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

IF OBJECT_ID('dbo.v_client_emp_site', 'V') IS NOT NULL
    DROP VIEW dbo.v_client_emp_site;
GO

CREATE OR ALTER   VIEW [dbo].[v_client_emp_site] AS
SELECT client_id, emp_id, MIN(site_name)  AS site_name
FROM dbo.attendance
WHERE site_name IS NOT NULL
GROUP BY client_id, emp_id
GO

