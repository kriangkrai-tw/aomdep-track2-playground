package com.example.orderservice.contract;

import au.com.dius.pact.consumer.MockServer;
import au.com.dius.pact.consumer.dsl.LambdaDsl;
import au.com.dius.pact.consumer.dsl.PactDslWithProvider;
import au.com.dius.pact.consumer.junit5.PactConsumerTestExt;
import au.com.dius.pact.consumer.junit5.PactTestFor;
import au.com.dius.pact.core.model.PactSpecVersion;
import au.com.dius.pact.core.model.RequestResponsePact;
import au.com.dius.pact.core.model.annotations.Pact;
import com.example.orderservice.client.UserClient;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Consumer-side Pact test for OrderService → UserService interaction.
 *
 * Running this test:
 *   cd order-service && mvn test
 *
 * A pact JSON file is written to target/pacts/ on success.
 * Publish it to the Pact Broker with:
 *   mvn pact:publish
 */
@ExtendWith(PactConsumerTestExt.class)
@PactTestFor(providerName = "UserService", pactVersion = PactSpecVersion.V3)
class UserClientPactTest {

    @Pact(consumer = "OrderService", provider = "UserService")
    public RequestResponsePact getUserById(PactDslWithProvider builder) {
        return builder
                .given("User with ID 1 exists")
                .uponReceiving("a request for User 1 details")
                    .path("/users/1")
                    .method("GET")
                .willRespondWith()
                    .status(200)
                    .body(LambdaDsl.newJsonBody(body -> {
                        body.numberType("id", 1);
                        body.stringType("name", "Alice");
                        body.stringType("email", "alice@example.com");
                    }).build())
                .toPact();
    }

    @Pact(consumer = "OrderService", provider = "UserService")
    public RequestResponsePact getUserById2(PactDslWithProvider builder) {
        return builder
                .given("User with ID 2 exists")
                .uponReceiving("a request for User 2 details")
                    .path("/users/2")
                    .method("GET")
                .willRespondWith()
                    .status(200)
                    .body(LambdaDsl.newJsonBody(body -> {
                        body.numberType("id", 2);
                        body.stringType("name", "Cho");
                        body.stringType("email", "cho@example.com");
                    }).build())
                .toPact();
    }

    @Test
    @PactTestFor(pactMethod = "getUserById")
    void testGetUserById(MockServer mockServer) {
        UserClient client = new UserClient(mockServer.getUrl());

        Map<String, Object> user = client.getUserById(1);

        assertThat(user).containsKey("id");
        assertThat(user.get("name")).isEqualTo("Alice");
        assertThat(user.get("email")).isEqualTo("alice@example.com");
    }

    @Test
    @PactTestFor(pactMethod = "getUserById2")
    void testGetUserById2(MockServer mockServer) {
        UserClient client = new UserClient(mockServer.getUrl());

        Map<String, Object> user = client.getUserById(2);

        assertThat(user).containsKey("id");
        assertThat(user.get("name")).isEqualTo("Cho");
        assertThat(user.get("email")).isEqualTo("cho@example.com");
    }
}
