$server = ".\SQLEXPRESS"
$database = "MyAppDB_DEV"

# Create / update database
.\scripts\run_migrations.ps1 -server $server -database $database
