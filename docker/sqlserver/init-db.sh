#!/bin/bash
set -e

echo "Starting SQL Server..."
/opt/mssql/bin/sqlservr &

echo "Waiting for SQL Server to start..."
sleep 20

echo "Running base DB creation (objects)..."
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$sa" -i /db/database/deploy/build-dev-db.sql

echo "Running migrations..."
for file in $(ls /db/database/migrations/*.sql | sort); do
    echo "Applying migration: $file"
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$sa" -i "$file"
done

echo "All done."
wait
