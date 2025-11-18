#!/bin/bash
set -e

echo "==========================================="
echo "   Environment selected: $ENVIRONMENT"
echo "==========================================="

# Wait until SQL Server responds
RETRIES=30
echo "Waiting for SQL Server to be available..."

until /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" >/dev/null 2>&1; do
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
# BUILD
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

apply_folder() {
  local title="$1"
  local folder="$2"

  echo "Applying $title..."

  shopt -s nullglob
  for f in "$folder"/*.sql; do
    echo "Running $f"
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i "$f"
  done
}

apply_folder "TABLES"          "/db/objects/tables"
apply_folder "FUNCTIONS"       "/db/objects/functions"
apply_folder "STORED PROCEDURES" "/db/objects/stored procedures"
apply_folder "VIEWS"           "/db/objects/views"


###########################################################
# MIGRATIONS
###########################################################

MIGRATIONS_FOLDER="/db/migration/$ENVIRONMENT"

if [ -d "$MIGRATIONS_FOLDER" ]; then
  echo "Running migrations in: $MIGRATIONS_FOLDER"
  shopt -s nullglob
  for f in "$MIGRATIONS_FOLDER"/*.sql; do
    echo "Running migration: $f"
    /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i "$f"
  done
else
  echo "No migrations found for environment $ENVIRONMENT"
fi


###########################################################
# SEED
###########################################################

SEED_FILE="/db/seed-data/${ENVIRONMENT}_seed.sql"

if [ -f "$SEED_FILE" ]; then
  echo "Running seed: $SEED_FILE"
  /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -i "$SEED_FILE"
else
  echo "No seed file found for environment $ENVIRONMENT"
fi


echo "==========================================="
echo "    DATABASE INITIALIZATION COMPLETED"
echo "==========================================="
