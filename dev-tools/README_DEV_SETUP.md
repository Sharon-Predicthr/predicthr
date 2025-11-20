# PredictHR – Local Database Setup

This folder contains tools for developers to easily create a full local PredictHR_DEV database.

## Requirements
1. Docker Desktop  
2. SSMS or Azure Data Studio  
3. Git + PowerShell

## How to create the local DB
Run ONE of the following:

### Option 1 – Windows PowerShell  
Right-click → “Run with PowerShell”
```
dev-tools/run-dev-db.ps1
```

### Option 2 – Double click (Windows)
```
dev-tools/run-dev-db.bat
```

## Connection info (SSMS)
- Server: `localhost,1433`
- User: `sa`
- Password: from your `.env`
- Database: `PredictHR_DEV`

## Notes
- Running this script will rebuild the entire DB from scratch.
- Safe for development.
