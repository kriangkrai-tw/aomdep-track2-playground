FROM maven:3.9.11-eclipse-temurin-25 AS build
ARG TARGETARCH
ARG TEMURIN_JDK_25_0_2_AARCH64_URL=https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.2%2B10/OpenJDK25U-jdk_aarch64_linux_hotspot_25.0.2_10.tar.gz
ARG TEMURIN_JDK_25_0_2_X64_URL=https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.2%2B10/OpenJDK25U-jdk_x64_linux_hotspot_25.0.2_10.tar.gz
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && case "${TARGETARCH}" in \
      arm64) JDK_URL="${TEMURIN_JDK_25_0_2_AARCH64_URL}" ;; \
      amd64) JDK_URL="${TEMURIN_JDK_25_0_2_X64_URL}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && mkdir -p /opt/java/exact \
 && curl -fsSL "${JDK_URL}" -o /tmp/jdk.tar.gz \
 && tar -xzf /tmp/jdk.tar.gz -C /opt/java/exact --strip-components=1 \
 && rm /tmp/jdk.tar.gz
ENV JAVA_HOME=/opt/java/exact
ENV PATH="${JAVA_HOME}/bin:${PATH}"
WORKDIR /workspace
COPY pom.xml .
COPY src src
RUN java -version && mvn -q package

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /opt/java/exact /opt/java/exact
ENV JAVA_HOME=/opt/java/exact
ENV PATH="${JAVA_HOME}/bin:${PATH}"
COPY --from=build /workspace/target/tracing-poc-backend-sdk-0.0.1-SNAPSHOT.jar /app/app.jar
EXPOSE 8080 8081
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
