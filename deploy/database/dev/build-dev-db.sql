PRINT '=== Starting DEV database build ===';
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'PredictHR_DEV')
BEGIN
    PRINT 'Creating DEV database...';
    CREATE DATABASE PredictHR_DEV;
END
GO

PRINT 'Switching context to PredictHR_DEV...';
USE PredictHR_DEV;
GO

PRINT 'Applying base objects...';

:r ..\\objects\\tables\\001_attendance_rejects_table.sql
:r ..\\objects\\tables\\002_attendance_table.sql
:r ..\\objects\\tables\\003_calculated_data_table.sql
:r ..\\objects\\tables\\004_emp_day_legit_table.sql
:r ..\\objects\\tables\\005_emp_sessions_table.sql
:r ..\\objects\\tables\\006_emp_work_calendar_table.sql
:r ..\\objects\\tables\\007_interventions_table.sql
:r ..\\objects\\tables\\008_legit_abs_blocks_table.sql
:r ..\\objects\\tables\\009_report_flight_table.sql
:r ..\\objects\\tables\\010_report_integrity_table.sql
:r ..\\objects\\tables\\011_report_workload_table.sql
:r ..\\objects\\tables\\012_risk_config_table.sql
:r ..\\objects\\tables\\013_risk_interventions_table.sql
:r ..\\objects\\tables\\014_work_calendar_dept_table.sql
:r ..\\objects\\tables\\015_work_calendar_table.sql

:r ..\\objects\\views\\001_v_client_emp_department.sql
:r ..\\objects\\views\\002_v_client_emp_role.sql
:r ..\\objects\\views\\003_v_client_emp_site.sql

:r ..\\objects\\procedures\\001_usp_infer_work_calendar.sql
:r ..\\objects\\procedures\\002_usp_build_dept_calendar.sql
:r ..\\objects\\procedures\\003_usp_detect_legit_absences.sql
:r ..\\objects\\procedures\\004_usp_build_emp_work_calendar.sql
:r ..\\objects\\procedures\\005_usp_update_adjusted_metrics.sql
:r ..\\objects\\procedures\\006_usp_calc_sessions.sql
:r ..\\objects\\procedures\\007_usp_calc_metrics.sql
:r ..\\objects\\procedures\\008_usp_report_window.sql
:r ..\\objects\\procedures\\009_usp_report_flight.sql
:r ..\\objects\\procedures\\010_usp_report_integrity.sql
:r ..\\objects\\procedures\\011_usp_report_workload.sql
:r ..\\objects\\procedures\\012_usp_report_sessions.sql
:r ..\\objects\\procedures\\013_usp_load_client_data.sql

PRINT '=== Base DB created — migrations will run from shell ===';
GO
