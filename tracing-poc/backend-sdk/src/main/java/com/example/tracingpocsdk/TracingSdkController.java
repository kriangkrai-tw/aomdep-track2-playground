package com.example.tracingpocsdk;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanContext;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@CrossOrigin(origins = {"http://localhost:5173", "http://127.0.0.1:5173"})
@RestController
@RequestMapping("/api")
public class TracingSdkController {
    private static final Logger logger = LoggerFactory.getLogger(TracingSdkController.class);

    @GetMapping("/trace")
    TraceResponse trace(@RequestHeader HttpHeaders headers) {
        SpanContext spanContext = Span.current().getSpanContext();
        String incomingTraceparent = valueOrPlaceholder(headers.getFirst("traceparent"));

        logger.info(
            "Handling downstream trace request traceId={} spanId={} incomingTraceparent={}",
            valueOrPlaceholder(spanContext.getTraceId()),
            valueOrPlaceholder(spanContext.getSpanId()),
            incomingTraceparent
        );

        return new TraceResponse(
            "Spring received the browser trace context via the OpenTelemetry Spring Boot starter.",
            "tracing-poc-backend-sdk",
            "spring-boot-starter",
            valueOrPlaceholder(spanContext.getTraceId()),
            valueOrPlaceholder(spanContext.getSpanId()),
            incomingTraceparent,
            Instant.now()
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
        Instant observedAt
    ) {
    }
}
