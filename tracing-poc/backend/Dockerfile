FROM curlimages/curl:8.8.0 AS otel
WORKDIR /otel
RUN curl -fsSL -o opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar

FROM maven:3.9.8-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml .
COPY src src
RUN mvn -q package

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=otel /otel/opentelemetry-javaagent.jar /otel/opentelemetry-javaagent.jar
COPY --from=build /workspace/target/tracing-poc-backend-0.0.1-SNAPSHOT.jar /app/app.jar
ENV OTEL_SERVICE_NAME=tracing-poc-backend
ENV OTEL_RESOURCE_ATTRIBUTES=service.namespace=tracing-poc,deployment.environment=local
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=none
ENV OTEL_LOGS_EXPORTER=none
ENV OTEL_EXPORTER_OTLP_PROTOCOL=grpc
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://alloy:4317
ENV OTEL_PROPAGATORS=tracecontext,baggage
ENV OTEL_INSTRUMENTATION_LOGBACK_MDC_ENABLED=true
EXPOSE 8080
ENTRYPOINT ["java", "-javaagent:/otel/opentelemetry-javaagent.jar", "-jar", "/app/app.jar"]
