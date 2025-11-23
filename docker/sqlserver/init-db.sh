#!/bin/bash
set -e

echo "==========================================="
echo "   Environment selected: $ENVIRONMENT"
echo "==========================================="

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

###########################################################
# BUILD (per environment)
###########################################################

BUILD_SCRIPT="/db/deploy/$ENVIRONMENT/build-dev-db.sql"
if [ ! -f "$BUILD_SCRIPT" ]; then
  echo "ERROR: Build script not found: $BUILD_SCRIPT"
  exit 1
fi

echo "Running build script: $BUILD_SCRIPT"

 /opt/mssql-tools/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -i "$BUILD_SCRIPT"

###########################################################
# OBJECTS
###########################################################

echo "Applying TABLES..."
for f in /db/objects/tables/*.sql; do
  echo "Running $f"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i "$f"
done

#echo "Applying FUNCTIONS..."
#for f in /db/objects/functions/*.sql; do
#  echo "Running $f"
#  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i "$f"
#done

echo "Applying STORED PROCEDURES..."
for f in /db/objects/stored_procedures/*.sql; do
  echo "Running $f"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i "$f"
done

echo "Applying VIEWS..."
for f in /db/objects/views/*.sql; do
  echo "Running $f"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i "$f"
done

###########################################################
# MIGRATIONS
###########################################################

MIGRATIONS_FOLDER="/db/migration/$ENVIRONMENT"
if [ -d "$MIGRATIONS_FOLDER" ]; then
  echo "Running migrations in: $MIGRATIONS_FOLDER"
  for f in "$MIGRATIONS_FOLDER"/*.sql; do
    echo "Running migration: $f"
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i "$f"
  done
else
  echo "No migrations found for environment $ENVIRONMENT"
fi

###########################################################
# SEEDS
###########################################################

SEED_FILE="/db/seed-data/${ENVIRONMENT}_seed.sql"
if [ -f "$SEED_FILE" ]; then
  echo "DEBUG: SEED FILE FOUND: $SEED_FILE"

  # Debug query BEFORE running seed file (NO -i here)
  /opt/mssql-tools/bin/sqlcmd \
      -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
      -Q "PRINT 'SEED DEBUG: starting'; SELECT DB_NAME() AS current_db;"

  echo "Running seed: $SEED_FILE"

  # Actual seed execution (NO -Q here)
  /opt/mssql-tools/bin/sqlcmd \
      -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
      -i "$SEED_FILE"
else
  echo "No seed file found for environment $ENVIRONMENT"
fi

echo "==========================================="
echo "    DATABASE INITIALIZATION COMPLETED"
echo "==========================================="

tail -f /dev/null
