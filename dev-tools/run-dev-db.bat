@echo off
echo ==================================
echo  PredictHR - Start DEV Database
echo ==================================

powershell -ExecutionPolicy Bypass -File "%~dp0run-dev-db.ps1"
pause
