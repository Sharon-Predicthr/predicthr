FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

ENV ACCEPT_EULA=Y
ENV MSSQL_SA_PASSWORD=P@ssw0rd123!

RUN mkdir -p /db

COPY ./deploy/database /db/deploy
COPY ./database/migration /db/migration
COPY ./database/objects /db/objects
COPY ./database/seed-data /db/seed-data

COPY ./docker/sqlserver/init-db.sh /db/init-db.sh
RUN chmod +x /db/init-db.sh

USER mssql

CMD /bin/bash -c "/opt/mssql/bin/sqlservr & sleep 20 && /db/init-db.sh"
