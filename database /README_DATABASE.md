Database Management Guide (SQL Express Compatible)
📂 Folder Structure
/database
   /baseline
   /migrations
   /scripts
   /deploy
   migration_history.sql
   README_DATABASE.md

🎯 Goal

Version-controlled SQL Server Express database

Repeatable migrations

Environment-based deployments (DEV/QA/MAIN)

Ability to create a fresh DB in seconds

CI/CD automation with GitHub Actions

🚀 How to Create a New Local Database
1. Create baseline schema:
sqlcmd -S .\SQLEXPRESS -i database/baseline/schema.sql
sqlcmd -S .\SQLEXPRESS -i database/baseline/data.sql

2. Run migrations:
powershell.exe -File database/scripts/run_migrations.ps1

🔧 How to Add a Migration

Create a new file in /database/migrations:

0011_add_new_view.sql


Use template:

IF NOT EXISTS (SELECT 1 FROM MigrationHistory WHERE MigrationName = '0011_add_new_view')
BEGIN

-- SQL CODE HERE

INSERT INTO MigrationHistory(MigrationName) VALUES('0011_add_new_view');
END;


Commit + push → CI/CD deploys automatically.

🔄 Branch-to-Database Relation
Branch	DB	Description
dev	MyAppDB_DEV	All new migrations
qa	MyAppDB_QA	Stable migrations under testing
main	MyAppDB	Production-ready migrations
🧪 CI/CD

DEV → Automatic migrations in GitHub Runner

QA → Automatic migrations

MAIN → Runs deploy_prod.ps1
