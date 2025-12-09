# PredictHR_DB — Database Structure & Migration Flow

This folder manages:
- Full DB schema
- Migrations
- Default data
- Views, functions, procedures
- Deployment automation
- CI/CD flows

## Branch Strategy

DEV → QA → MAIN (PROD)

Only migrations are merged upward.
No direct edits on QA/MAIN.

## Local Developer Setup

1. Install SQL Express
2. Clone repo
3. Run:

PowerShell:
  scripts/run_local_migrations.ps1

or Linux/Mac:
  scripts/run_local_migrations.sh

## CI/CD

GitHub Actions runs:
- validate SQL
- apply migrations to DEV/QA
- create build DB from scratch
