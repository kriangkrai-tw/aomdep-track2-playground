package com.example.todoservice.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Lightweight probe endpoints for generating observable traffic in Dynatrace.
 * GET /hello  → 200 with a JSON greeting
 * GET /error  → 500 — throws a RuntimeException to generate error traces and logs
 */
@RestController
public class ProbeController {

    private static final Logger log = LoggerFactory.getLogger(ProbeController.class);

    @GetMapping("/hello")
    public ResponseEntity<Map<String, String>> hello() {
        log.info("Probe: GET /hello called");
        return ResponseEntity.ok(Map.of(
                "message", "Hello from todo-service!",
                "service", "todo-service",
                "status", "ok"
        ));
    }

    @GetMapping("/error")
    public void error() {
        log.error("Probe: GET /error called — throwing simulated exception for observability testing");
        throw new RuntimeException("Simulated error for Dynatrace observability testing");
    }
}
