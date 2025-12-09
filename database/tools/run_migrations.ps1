$server = ".\SQLEXPRESS"
$database = "MyAppDB"
$migrationPath = "database\migrations"

# Ensure DB exists
sqlcmd -S $server -Q "IF DB_ID('$database') IS NULL CREATE DATABASE [$database];"

# Ensure MigrationHistory exists
sqlcmd -S $server -d $database -i "database\migration_history.sql"

# Run all migrations
Get-ChildItem $migrationPath -Filter *.sql | Sort-Object Name | ForEach-Object {
    $file = $_.FullName
    Write-Host "Running migration: $file"
    sqlcmd -S $server -d $database -i $file
}
