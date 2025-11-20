Write-Host "Checking Docker availability..." -ForegroundColor Cyan

$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Host "ERROR: Docker is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

$running = docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker Desktop is not running." -ForegroundColor Red
    exit 1
}

Write-Host "Docker is installed and running." -ForegroundColor Green
