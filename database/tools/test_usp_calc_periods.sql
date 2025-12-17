-- ============================================================================
-- Test Script: usp_calc_periods Stored Procedure
-- Purpose: Validate the stored procedure execution and results
-- ============================================================================

USE PredictHR_DEV;
GO

PRINT '========================================';
PRINT 'Testing usp_calc_periods Procedure';
PRINT '========================================';
GO

-- ============================================================================
-- STEP 1: Check if procedure exists
-- ============================================================================
PRINT '';
PRINT 'STEP 1: Verifying procedure exists...';
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_calc_periods' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    PRINT '✓ Procedure usp_calc_periods exists';
END
ELSE
BEGIN
    PRINT '✗ ERROR: Procedure usp_calc_periods does not exist!';
    RETURN;
END
GO

-- ============================================================================
-- STEP 2: Check required configuration values
-- ============================================================================
PRINT '';
PRINT 'STEP 2: Checking configuration values...';
DECLARE @test_client_id NVARCHAR(50) = 'TEST_CLIENT'; -- Change to your actual client_id
DECLARE @baseline_months INT;
DECLARE @recent_months INT;

-- Get or set baseline_months
SELECT TOP(1) @baseline_months = TRY_CAST(config_value AS INT)
FROM dbo.risk_config
WHERE (client_id = @test_client_id OR client_id IS NULL) 
  AND config_key = N'baseline_months'
ORDER BY CASE WHEN client_id = @test_client_id THEN 0 ELSE 1 END;

IF @baseline_months IS NULL SET @baseline_months = 9; -- Default

-- Get or set recent_months
SELECT TOP(1) @recent_months = TRY_CAST(config_value AS INT)
FROM dbo.risk_config
WHERE (client_id = @test_client_id OR client_id IS NULL) 
  AND config_key = N'recent_months'
ORDER BY CASE WHEN client_id = @test_client_id THEN 0 ELSE 1 END;

IF @recent_months IS NULL SET @recent_months = 3; -- Default

PRINT '  baseline_months: ' + CAST(@baseline_months AS NVARCHAR(10));
PRINT '  recent_months: ' + CAST(@recent_months AS NVARCHAR(10));
GO

-- ============================================================================
-- STEP 3: Check if client has required data
-- ============================================================================
PRINT '';
PRINT 'STEP 3: Checking data availability...';
DECLARE @test_client_id NVARCHAR(50) = 'TEST_CLIENT'; -- Change to your actual client_id

DECLARE @has_work_calendar INT = 0;
DECLARE @has_emp_sessions INT = 0;
DECLARE @has_emp_work_calendar INT = 0;
DECLARE @last_workday DATE;

SELECT @has_work_calendar = COUNT(*)
FROM dbo.work_calendar
WHERE client_id = @test_client_id;

SELECT @has_emp_sessions = COUNT(*)
FROM dbo.emp_sessions
WHERE client_id = @test_client_id;

SELECT @has_emp_work_calendar = COUNT(*)
FROM dbo.emp_work_calendar
WHERE client_id = @test_client_id;

SELECT TOP(1) @last_workday = MAX(calendar_date)
FROM dbo.work_calendar
WHERE client_id = @test_client_id AND is_workday = 1;

PRINT '  work_calendar records: ' + CAST(@has_work_calendar AS NVARCHAR(10));
PRINT '  emp_sessions records: ' + CAST(@has_emp_sessions AS NVARCHAR(10));
PRINT '  emp_work_calendar records: ' + CAST(@has_emp_work_calendar AS NVARCHAR(10));
PRINT '  last_company_workday: ' + ISNULL(CAST(@last_workday AS NVARCHAR(20)), 'NULL');

IF @has_work_calendar = 0 OR @last_workday IS NULL
BEGIN
    PRINT '✗ WARNING: No work_calendar data found for client. Procedure may not execute.';
END
GO

-- ============================================================================
-- STEP 4: Check eligible employees (before execution)
-- ============================================================================
PRINT '';
PRINT 'STEP 4: Checking eligible employees...';
DECLARE @test_client_id NVARCHAR(50) = 'TEST_CLIENT'; -- Change to your actual client_id
DECLARE @last_company_workday DATE;

SELECT TOP(1) @last_company_workday = MAX(calendar_date)
FROM dbo.work_calendar
WHERE client_id = @test_client_id AND is_workday = 1;

IF @last_company_workday IS NOT NULL
BEGIN
    SELECT 
        COUNT(*) AS eligible_employees_count,
        MIN(emp_work_start) AS earliest_work_start,
        MAX(last_emp_workday) AS latest_workday
    FROM 
    (
        SELECT 
            ewc.client_id,
            ewc.emp_id,
            COALESCE(emp.work_start, ewc.first_session_date) AS emp_work_start,
            ewc.last_session_date AS last_emp_workday
        FROM 
        (
            SELECT 
                client_id,
                emp_id,
                MIN(CAST(calendar_date AS DATE)) AS first_session_date,
                MAX(CAST(calendar_date AS DATE)) AS last_session_date
            FROM dbo.emp_work_calendar
            WHERE client_id = @test_client_id AND is_working = 1
            GROUP BY client_id, emp_id
        ) AS ewc
        LEFT JOIN dbo.employees emp
            ON ewc.client_id = emp.client_id AND ewc.emp_id = emp.emp_id
        WHERE 
            COALESCE(emp.work_start, ewc.first_session_date) <= DATEADD(MONTH, -6, @last_company_workday)
            AND ewc.last_session_date >= DATEADD(MONTH, -2, @last_company_workday)
    ) AS eligible;
    
    PRINT '  Eligible employees found (employees with 6+ months tenure and active in past 2 months)';
END
ELSE
BEGIN
    PRINT '  ✗ Cannot determine eligible employees - no work_calendar data';
END
GO

-- ============================================================================
-- STEP 5: Execute the stored procedure
-- ============================================================================
PRINT '';
PRINT 'STEP 5: Executing usp_calc_periods...';
PRINT '  Start time: ' + CONVERT(NVARCHAR(50), GETDATE(), 120);
DECLARE @test_client_id NVARCHAR(50) = 'TEST_CLIENT'; -- Change to your actual client_id
DECLARE @start_time DATETIME2 = SYSDATETIME();

BEGIN TRY
    EXEC dbo.usp_calc_periods @client_id = @test_client_id;
    
    DECLARE @end_time DATETIME2 = SYSDATETIME();
    DECLARE @duration_ms INT = DATEDIFF(MILLISECOND, @start_time, @end_time);
    
    PRINT '  ✓ Procedure executed successfully';
    PRINT '  Duration: ' + CAST(@duration_ms AS NVARCHAR(10)) + ' ms';
END TRY
BEGIN CATCH
    PRINT '  ✗ ERROR executing procedure:';
    PRINT '    Error Number: ' + CAST(ERROR_NUMBER() AS NVARCHAR(10));
    PRINT '    Error Message: ' + ERROR_MESSAGE();
    PRINT '    Error Severity: ' + CAST(ERROR_SEVERITY() AS NVARCHAR(10));
    PRINT '    Error State: ' + CAST(ERROR_STATE() AS NVARCHAR(10));
    RETURN;
END CATCH
GO

-- ============================================================================
-- STEP 6: Validate results
-- ============================================================================
PRINT '';
PRINT 'STEP 6: Validating results...';
DECLARE @test_client_id NVARCHAR(50) = 'TEST_CLIENT'; -- Change to your actual client_id

DECLARE @rows_inserted INT;
SELECT @rows_inserted = COUNT(*)
FROM dbo.calc_period_metrics
WHERE client_id = @test_client_id;

PRINT '  Rows inserted: ' + CAST(@rows_inserted AS NVARCHAR(10));

IF @rows_inserted = 0
BEGIN
    PRINT '  ⚠ WARNING: No rows inserted. Check:';
    PRINT '    1. Client has eligible employees (6+ months, active in past 2 months)';
    PRINT '    2. Employee has work sessions in the calculated periods';
    PRINT '    3. Configuration values are set correctly';
END
ELSE
BEGIN
    PRINT '  ✓ Data inserted successfully';
END
GO

-- ============================================================================
-- STEP 7: Sample data validation
-- ============================================================================
PRINT '';
PRINT 'STEP 7: Sample data check (first 5 rows)...';
DECLARE @test_client_id NVARCHAR(50) = 'TEST_CLIENT'; -- Change to your actual client_id

SELECT TOP 5
    emp_id,
    recent_start,
    recent_end,
    baseline_start,
    baseline_end,
    workdays_r,
    workdays_b,
    presence_r,
    presence_b,
    presence_pct_r,
    presence_pct_b,
    avg_minutes_r,
    avg_minutes_b
FROM dbo.calc_period_metrics
WHERE client_id = @test_client_id
ORDER BY emp_id;
GO

-- ============================================================================
-- STEP 8: Data quality checks
-- ============================================================================
PRINT '';
PRINT 'STEP 8: Data quality validation...';
DECLARE @test_client_id NVARCHAR(50) = 'TEST_CLIENT'; -- Change to your actual client_id

-- Check for NULL values in critical fields
DECLARE @null_counts TABLE (field_name NVARCHAR(50), null_count INT);

INSERT INTO @null_counts VALUES
    ('emp_id', (SELECT COUNT(*) FROM dbo.calc_period_metrics WHERE client_id = @test_client_id AND emp_id IS NULL)),
    ('recent_start', (SELECT COUNT(*) FROM dbo.calc_period_metrics WHERE client_id = @test_client_id AND recent_start IS NULL)),
    ('workdays_r', (SELECT COUNT(*) FROM dbo.calc_period_metrics WHERE client_id = @test_client_id AND workdays_r IS NULL)),
    ('presence_r', (SELECT COUNT(*) FROM dbo.calc_period_metrics WHERE client_id = @test_client_id AND presence_r IS NULL));

SELECT * FROM @null_counts WHERE null_count > 0;

IF NOT EXISTS (SELECT 1 FROM @null_counts WHERE null_count > 0)
BEGIN
    PRINT '  ✓ No NULL values found in critical fields';
END
ELSE
BEGIN
    PRINT '  ⚠ WARNING: NULL values found in some fields';
END
GO

-- Check percentage calculations (should be between 0 and 1)
PRINT '';
PRINT 'STEP 9: Percentage validation...';
DECLARE @test_client_id NVARCHAR(50) = 'TEST_CLIENT'; -- Change to your actual client_id

SELECT 
    COUNT(*) AS total_rows,
    SUM(CASE WHEN presence_pct_r < 0 OR presence_pct_r > 1 THEN 1 ELSE 0 END) AS invalid_presence_pct_r,
    SUM(CASE WHEN presence_pct_b < 0 OR presence_pct_b > 1 THEN 1 ELSE 0 END) AS invalid_presence_pct_b,
    SUM(CASE WHEN absence_pct_r < 0 OR absence_pct_r > 1 THEN 1 ELSE 0 END) AS invalid_absence_pct_r,
    SUM(CASE WHEN absence_pct_b < 0 OR absence_pct_b > 1 THEN 1 ELSE 0 END) AS invalid_absence_pct_b
FROM dbo.calc_period_metrics
WHERE client_id = @test_client_id;

PRINT '  ✓ Percentage values should be between 0.0 and 1.0';
GO

PRINT '';
PRINT '========================================';
PRINT 'Test completed!';
PRINT '========================================';
GO

