Param(
    [string]$Server = "localhost\SQLEXPRESS",
    [string]$Database = "PredictHR_DB_DEV"
)

Write-Host "Applying migrations to $Database ..."

$migs = Get-ChildItem "../database/migrations" -Filter "*.sql"

foreach ($mig in $migs) {
    Write-Host "Running $($mig.Name)"
    sqlcmd -S $Server -d $Database -i $mig.FullName
}
