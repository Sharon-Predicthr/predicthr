Write-Host "=== PredictHR - Database Setup ===" -ForegroundColor Cyan

Write-Host "Stopping and removing old environment..." -ForegroundColor Yellow
docker compose down -v

Write-Host "Building and starting SQL Server + Database..." -ForegroundColor Yellow
docker compose up -d --build

Write-Host "Waiting for SQL Server to finish startup..." -ForegroundColor Yellow
Start-Sleep -Seconds 20

Write-Host ""
Write-Host "========================================"
Write-Host "✔ PredictHR_DEV database is ready!"
Write-Host "========================================"
Write-Host ""
Write-Host "Connect using SSMS:"
Write-Host "  Server: localhost,1433"
Write-Host "  User:   sa"
Write-Host "  Pass:   (from .env)"
Write-Host ""
Write-Host "Done." -ForegroundColor Green
