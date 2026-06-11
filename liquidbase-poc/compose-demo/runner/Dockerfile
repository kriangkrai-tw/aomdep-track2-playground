# Apply mode 2: an Ubuntu container with the Liquibase CLI installed.
# Built to mirror what an actions/runner step would look like, so the
# `apply.sh` script doubles as the body of a future GHA "run liquibase" step.
FROM ubuntu:24.04

ARG LIQUIBASE_VERSION=4.27.0
ARG MSSQL_JDBC_VERSION=12.6.1.jre11
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openjdk-17-jre-headless \
      ca-certificates \
      curl \
      tar \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/liquibase \
 && curl -fsSL "https://github.com/liquibase/liquibase/releases/download/v${LIQUIBASE_VERSION}/liquibase-${LIQUIBASE_VERSION}.tar.gz" \
      -o /tmp/liquibase.tar.gz \
 && tar -xzf /tmp/liquibase.tar.gz -C /opt/liquibase \
 && rm /tmp/liquibase.tar.gz \
 && ln -s /opt/liquibase/liquibase /usr/local/bin/liquibase

RUN curl -fsSL \
      "https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/${MSSQL_JDBC_VERSION}/mssql-jdbc-${MSSQL_JDBC_VERSION}.jar" \
      -o /opt/liquibase/lib/mssql-jdbc-${MSSQL_JDBC_VERSION}.jar

WORKDIR /workspace
COPY apply.sh /usr/local/bin/apply.sh
RUN chmod +x /usr/local/bin/apply.sh

ENTRYPOINT ["/usr/local/bin/apply.sh"]
CMD ["update"]
