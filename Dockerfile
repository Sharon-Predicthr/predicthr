FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

ENV ACCEPT_EULA=Y

# חייבים להכניס סיסמה בזמן build כי הסביבה תוחלף ב-runtime
ARG MSSQL_SA_PASSWORD=TempPass123!
ENV MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD

# התקנת sqlcmd (חובה!)
RUN apt-get update && \
    apt-get install -y curl gnupg && \
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list \
        > /etc/apt/sources.list.d/msprod.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y mssql-tools unixodbc-dev && \
    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc

RUN mkdir -p /db

COPY ./deploy/database /db/deploy
COPY ./database/migration /db/migration
COPY ./database/objects /db/objects
COPY ./database/seed-data /db/seed-data

COPY ./docker/sqlserver/init-db.sh /db/init-db.sh
RUN chmod +x /db/init-db.sh

USER mssql

ENTRYPOINT ["/bin/bash", "/db/init-db.sh"]
