#!/bin/bash

SERVER="localhost\\SQLEXPRESS"
DB="PredictHR_DB_DEV"

for f in ../database/migrations/*.sql; do
    echo "Running migration: $f"
    /opt/mssql-tools/bin/sqlcmd -S $SERVER -d $DB -i "$f"
done
