# ============================================================================
# Test Script: usp_calc_periods Stored Procedure
# Purpose: Execute test script via sqlcmd
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ClientId = "TEST_CLIENT",
    
    [Parameter(Mandatory=$false)]
    [string]$Server = "localhost,1433",
    
    [Parameter(Mandatory=$false)]
    [string]$Database = "PredictHR_DEV",
    
    [Parameter(Mandatory=$false)]
    [string]$User = "sa",
    
    [Parameter(Mandatory=$false)]
    [string]$Password = "MyStrongPass123!"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Testing usp_calc_periods Procedure" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Client ID: $ClientId" -ForegroundColor Yellow
Write-Host "Server: $Server" -ForegroundColor Yellow
Write-Host "Database: $Database" -ForegroundColor Yellow
Write-Host ""

# Check if sqlcmd is available
$sqlcmdPath = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmdPath) {
    Write-Host "ERROR: sqlcmd not found. Please install SQL Server command-line tools." -ForegroundColor Red
    exit 1
}

# Replace CLIENT_ID placeholder in SQL file
$testSqlFile = Join-Path $PSScriptRoot "test_usp_calc_periods.sql"
$tempSqlFile = [System.IO.Path]::GetTempFileName() + ".sql"

$sqlContent = Get-Content $testSqlFile -Raw
$sqlContent = $sqlContent -replace "TEST_CLIENT", $ClientId
$sqlContent | Out-File -FilePath $tempSqlFile -Encoding UTF8

try {
    # Execute the test script
    $connectionString = "-S $Server -d $Database -U $User -P $Password -i `"$tempSqlFile`""
    
    Write-Host "Executing test script..." -ForegroundColor Green
    Write-Host ""
    
    & sqlcmd $connectionString.Split(' ')
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Green
        Write-Host "Test completed successfully!" -ForegroundColor Green
        Write-Host "=========================================" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Red
        Write-Host "Test completed with errors (Exit code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "=========================================" -ForegroundColor Red
    }
}
finally {
    # Cleanup temp file
    if (Test-Path $tempSqlFile) {
        Remove-Item $tempSqlFile -Force
    }
}

