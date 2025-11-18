FROM mcr.microsoft.com/mssql/server:2022-latest

ENV ACCEPT_EULA=Y
ENV MSSQL_SA_PASSWORD=sa

# Create working folder
RUN mkdir -p /db

# Copy everything from ./docker/sqlserver to /db
COPY . /db

# Make scripts executable
RUN chmod +x /db/init-db.sh

# Start SQL Server, run initialization
CMD ["/bin/bash", "/db/init-db.sh"]
