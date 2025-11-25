PRINT '=== Starting DEV database build ===';

--------------------------------------------------------
-- 1. CREATE DATABASE IF NOT EXISTS
--------------------------------------------------------
IF NOT EXISTS (
    SELECT name FROM sys.databases WHERE name = 'PredictHR_DEV'
)
BEGIN
    PRINT 'Creating database PredictHR_DEV...';
    EXEC('CREATE DATABASE PredictHR_DEV');
END
ELSE
BEGIN
    PRINT 'Database PredictHR_DEV already exists.';
END
GO

--------------------------------------------------------
-- 2. SWITCH CONTEXT TO THE DATABASE
--------------------------------------------------------
USE PredictHR_DEV;
GO

PRINT 'Using database PredictHR_DEV';
PRINT 'Applying base objects...';

--------------------------------------------------------
-- 3. TABLES
--------------------------------------------------------
:r /db/objects/tables/001_attendance_rejects_table.sql
:r /db/objects/tables/002_attendance_table.sql
:r /db/objects/tables/003_calculated_data_table.sql
:r /db/objects/tables/004_emp_day_legit_table.sql
:r /db/objects/tables/005_emp_sessions_table.sql
:r /db/objects/tables/006_emp_work_calendar_table.sql
:r /db/objects/tables/007_interventions_table.sql
:r /db/objects/tables/008_legit_abs_blocks_table.sql
:r /db/objects/tables/009_report_flight_table.sql
:r /db/objects/tables/010_report_integrity_table.sql
:r /db/objects/tables/011_report_workload_table.sql
:r /db/objects/tables/012_risk_config_table.sql
:r /db/objects/tables/013_risk_interventions_table.sql
:r /db/objects/tables/014_work_calendar_dept_table.sql
:r /db/objects/tables/015_work_calendar_table.sql
:r /db/objects/tables/016_attendance_staging_table.sql
            
--------------------------------------------------------
-- 4. VIEWS
--------------------------------------------------------
:r /db/objects/views/create_v_client_emp_department.sql
:r /db/objects/views/create_v_client_emp_role.sql
:r /db/objects/views/create_v_client_emp_site.sql

--------------------------------------------------------
-- 5. STORED PROCEDURES
--------------------------------------------------------
:r /db/objects/stored_procedures/001_usp_infer_work_calendar.sql
:r /db/objects/stored_procedures/002_usp_build_dept_calendar.sql
:r /db/objects/stored_procedures/003_usp_detect_legit_absences.sql
:r /db/objects/stored_procedures/004_usp_build_emp_work_calendar.sql
:r /db/objects/stored_procedures/005_usp_update_adjusted_metrics.sql
:r /db/objects/stored_procedures/006_usp_calc_sessions.sql
:r /db/objects/stored_procedures/007_usp_calc_metrics.sql
:r /db/objects/stored_procedures/008_usp_report_window.sql
:r /db/objects/stored_procedures/009_usp_calc_flight.sql
:r /db/objects/stored_procedures/010_usp_calc_integrity.sql    
:r /db/objects/stored_procedures/011_usp_calc_burnout.sql
:r /db/objects/stored_procedures/012_usp_report_sessions.sql
:r /db/objects/stored_procedures/013_usp_load_client_data.sql
:r /db/objects/stored_procedures/014_usp_load_client_data_v2.sql

PRINT '=== Base DB created — migrations will run from shell ===';
GO
