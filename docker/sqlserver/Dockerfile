FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

ENV ACCEPT_EULA=Y
ENV MSSQL_SA_PASSWORD=sa

RUN mkdir -p /db

COPY ./deploy/database /db/deploy
COPY ./database/migration /db/migration
COPY ./database/objects /db/objects
COPY ./database/seed-data /db/seed-data

COPY ./docker/sqlserver/init-db.sh /db/init-db.sh
COPY ./docker/sqlserver/entrypoint-wrapper.sh /entrypoint-wrapper.sh

RUN chmod +x /db/init-db.sh
RUN chmod +x /entrypoint-wrapper.sh

USER mssql

ENTRYPOINT ["/entrypoint-wrapper.sh"]
