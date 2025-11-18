#!/bin/bash
set -e

# Start SQL Server in background
/opt/mssql/bin/sqlservr &

echo "Waiting for SQL Server to start..."

# Wait until SQL Server responds
for i in {1..30}; do
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" &>/dev/null && break
    echo "SQL not ready... ($((30-i)) retries left)"
    sleep 2
done

# Run DB initialization script
echo "Running init-db.sh..."
/bin/bash /db/init-db.sh || true

echo "Initialization complete. SQL Server continues running."

# Keep SQL Server alive
wait -n
