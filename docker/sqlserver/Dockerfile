FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

ENV ACCEPT_EULA=Y
ENV MSSQL_SA_PASSWORD=sa

# Working folder
RUN mkdir -p /db

# Copy environment-specific DB scripts
COPY ./deploy/database /db/deploy
COPY ./database/objects /db/objects
COPY ./database/migration /db/migration
COPY ./database/seed-data /db/seed-data

# Copy init script
COPY ./docker/sqlserver/init-db.sh /db/init-db.sh
RUN chmod +x /db/init-db.sh

USER mssql

CMD ["/bin/bash", "/db/init-db.sh"]
