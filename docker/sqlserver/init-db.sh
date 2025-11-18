#!/bin/bash
echo "Waiting for SQL Server to start..."
sleep 20

echo "Running database initialization script..."

sqlcmd -S localhost,1433 \
    -U sa \
    -P "$MSSQL_SA_PASSWORD" \
    -i /db/database/deploy/build-dev-db.sql

echo "Database initialization completed."

# שמירת השרת בחיים
/opt/mssql/bin/sqlservr
