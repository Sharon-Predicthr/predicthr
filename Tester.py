-- Deep
cd C:\Proj\PredictHR\predicthr-main

$env:ENVIRONMENT="dev"
$env:MSSQL_SA_PASSWORD="MyStrongPass123!"

docker compose down -v

docker compose build --no-cache   # ← החלק שחסר אצלך
docker compose up -d

docker logs -f predict-hr-sql


-- Fast
cd C:\Proj\PredictHR\predicthr-main

$env:ENVIRONMENT="dev"
$env:MSSQL_SA_PASSWORD="MyStrongPass123!"

docker compose down -v
docker compose up -d --build
docker logs -f predict-hr-sql





-- Full container cleanning
docker compose down -v
docker builder prune -af
docker compose up -d --build
docker logs -f predict-hr-sql


-- directories
tree /f