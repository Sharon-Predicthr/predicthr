$env:ENVIRONMENT="dev"
$env:MSSQL_SA_PASSWORD="MyStrongPass123!"

docker compose down -v

docker compose build --no-cache   # ← החלק שחסר אצלך
docker compose up -d

docker logs -f predict-hr-sql