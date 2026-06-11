# Apply mode 3: thin migration image. Liquibase + MSSQL JDBC + the changelog,
# baked together. Built with the repo root as context so we can COPY the same
# changelog files the compose-demo Spring service uses.
FROM liquibase/liquibase:4.27

USER root
ARG MSSQL_JDBC_VERSION=12.6.1.jre11
ADD --chown=liquibase:liquibase \
    https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/${MSSQL_JDBC_VERSION}/mssql-jdbc-${MSSQL_JDBC_VERSION}.jar \
    /liquibase/lib/

# COPY the `db/` parent (not just db/changelog/) so include paths inside the
# master XML resolve from /liquibase the same way they resolve from the
# classpath in Spring Boot. Keeps DATABASECHANGELOG.FILENAME consistent.
COPY --chown=liquibase:liquibase \
    compose-demo/service/src/main/resources/db/ \
    /liquibase/db/

USER liquibase
