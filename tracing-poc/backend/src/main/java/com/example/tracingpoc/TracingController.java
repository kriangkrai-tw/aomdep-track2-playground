package com.example.tracingpoc;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import java.time.Instant;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.HttpHeaders;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

@CrossOrigin(origins = {"http://localhost:5173", "http://127.0.0.1:5173"})
@RestController
@RequestMapping("/api")
public class TracingController {
    private static final Logger logger = LoggerFactory.getLogger(TracingController.class);
    private final RestTemplate restTemplate;
    private final String sdkTraceUrl;

    public TracingController(
        RestTemplateBuilder restTemplateBuilder,
        @Value("${demo.sdk-base-url}") String sdkBaseUrl
    ) {
        this.restTemplate = restTemplateBuilder
            .setConnectTimeout(Duration.ofSeconds(5))
            .setReadTimeout(Duration.ofSeconds(5))
            .build();
        this.sdkTraceUrl = sdkBaseUrl.endsWith("/") ? sdkBaseUrl + "api/trace" : sdkBaseUrl + "/api/trace";
    }

    @GetMapping("/trace")
    TraceResponse trace(@RequestHeader HttpHeaders headers) {
        SpanContext spanContext = Span.current().getSpanContext();
        String incomingTraceparent = valueOrPlaceholder(headers.getFirst("traceparent"));

        logger.info(
            "Handling chained trace request traceId={} spanId={} incomingTraceparent={} downstreamUrl={}",
            valueOrPlaceholder(spanContext.getTraceId()),
            valueOrPlaceholder(spanContext.getSpanId()),
            incomingTraceparent,
            sdkTraceUrl
        );

        DownstreamTraceResponse downstreamBackend = restTemplate.getForObject(sdkTraceUrl, DownstreamTraceResponse.class);

        logger.info(
            "Downstream backend responded traceId={} spanId={} incomingTraceparent={}",
            downstreamBackend == null ? "missing" : valueOrPlaceholder(downstreamBackend.traceId()),
            downstreamBackend == null ? "missing" : valueOrPlaceholder(downstreamBackend.spanId()),
            downstreamBackend == null ? "missing" : valueOrPlaceholder(downstreamBackend.incomingTraceparent())
        );

        return new TraceResponse(
            "Spring received the browser trace context via the OpenTelemetry Java agent and called the downstream Spring service.",
            "tracing-poc-backend",
            "java-agent",
            valueOrPlaceholder(spanContext.getTraceId()),
            valueOrPlaceholder(spanContext.getSpanId()),
            incomingTraceparent,
            Instant.now(),
            downstreamBackend
        );
    }

    private String valueOrPlaceholder(String value) {
        return value == null || value.isBlank() ? "missing" : value;
    }

    record TraceResponse(
        String message,
        String serviceName,
        String instrumentationType,
        String traceId,
        String spanId,
        String incomingTraceparent,
        Instant observedAt,
        DownstreamTraceResponse downstreamBackend
    ) {
    }

    record DownstreamTraceResponse(
        String message,
        String serviceName,
        String instrumentationType,
        String traceId,
        String spanId,
        String incomingTraceparent,
        Instant observedAt
    ) {
    }
}
