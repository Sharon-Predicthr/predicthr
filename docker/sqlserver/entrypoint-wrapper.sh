#!/bin/bash
set -e

# Start SQL Server in background using the official entrypoint
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# Wait for SQL Server to be ready
echo "Waiting for SQL Server to start..."
sleep 20

# Wait until SQL is ready
RETRIES=30
until /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" >/dev/null 2>&1
do
    echo "SQL not ready... ($RETRIES retries left)"
    sleep 2
    RETRIES=$((RETRIES-1))
    if [ $RETRIES -le 0 ]; then
        echo "ERROR: SQL Server did not start!"
        exit 1
    fi
done

echo "SQL Server is ready."

# Run initialization script
/db/init-db.sh

# Keep container alive - wait for SQL Server process
wait $SQL_PID
