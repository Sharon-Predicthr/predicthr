$server = "QA-SQL\SQLEXPRESS"
$database = "MyAppDB_QA"

.\scripts\run_migrations.ps1 -server $server -database $database
