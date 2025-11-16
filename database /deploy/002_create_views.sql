
/* ---------- Views for Site, Department, Role ---------- */

CREATE OR ALTER VIEW v_client_emp_site AS
SELECT client_id, emp_id, MIN(site_name)  AS site_name
FROM dbo.attendance
GROUP BY client_id, emp_id, site_name

CREATE OR ALTER VIEW v_client_emp_department AS
SELECT client_id, emp_id, MIN(department) AS department
FROM dbo.attendance
GROUP BY client_id, emp_id, department

CREATE OR ALTER VIEW v_client_emp_role AS
SELECT client_id, emp_id, MIN(emp_role) AS emp_role
FROM dbo.attendance
GROUP BY client_id, emp_id, emp_role
