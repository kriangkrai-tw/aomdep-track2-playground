package com.example.orderservice.client;

import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.util.Map;

/**
 * HTTP client used by OrderService to fetch user details from UserService.
 * This is the class whose interactions are captured in the Pact consumer test.
 */
public class UserClient {

    private final WebClient webClient;

    public UserClient(String baseUrl) {
        this.webClient = WebClient.builder().baseUrl(baseUrl).build();
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> getUserById(int userId) {
        return webClient.get()
                .uri("/users/{id}", userId)
                .retrieve()
                .bodyToMono(Map.class)
                .map(m -> (Map<String, Object>) m)
                .block();
    }
}
