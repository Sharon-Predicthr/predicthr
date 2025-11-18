#!/bin/bash
set -e

echo "Starting SQL Server..."
/opt/mssql/bin/sqlservr &

# Wait for SQL Server
echo "Waiting for SQL Server to be available..."
sleep 15

echo "Running base DB script..."
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$sa" -i /db/database/deploy/build-dev-db.sql


echo "Running migrations..."
for file in $(ls /db/database/migrations/*.sql | sort); do
    echo "Applying migration: $file"
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$sa" -i "$file"
done

echo "=== ALL Done ==="
wait
