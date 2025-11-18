#!/bin/bash
set -e

# Start SQL Server in background
/opt/mssql/bin/sqlservr &

# Run your initialization script
/db/init-db.sh

# Keep container alive
wait
