package com.example.userservice.contract;

import au.com.dius.pact.provider.junit5.PactVerificationContext;
import au.com.dius.pact.provider.junit5.PactVerificationInvocationContextProvider;
import au.com.dius.pact.provider.junitsupport.Provider;
import au.com.dius.pact.provider.junitsupport.State;
import au.com.dius.pact.provider.junitsupport.loader.PactBroker;
import au.com.dius.pact.provider.junitsupport.loader.PactBrokerAuth;
import au.com.dius.pact.provider.spring.junit5.MockMvcTestTarget;
import com.example.userservice.controller.UserController;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.TestTemplate;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Provider-side Pact verification test.
 *
 * By default this fetches the pact from the Pact Broker at localhost:9292.
 *
 * To run against a LOCAL pact file instead, replace @PactBroker with:
 *   @PactFolder("../order-service/target/pacts")
 *
 * Run with:
 *   cd user-service && mvn test
 */
@WebMvcTest(UserController.class)
@Provider("UserService")
@PactBroker(
    host = "${pactbroker.host:localhost}",
    port = "${pactbroker.port:9292}"
)
@ExtendWith(PactVerificationInvocationContextProvider.class)
class UserServicePactVerificationTest {

    @Autowired
    private MockMvc mockMvc;

    @BeforeEach
    void setUp(PactVerificationContext context) {
        context.setTarget(new MockMvcTestTarget(mockMvc));
    }

    @TestTemplate
    void verifyPact(PactVerificationContext context) {
        context.verifyInteraction();
    }

    @State("User with ID 1 exists")
    void userWithId1Exists() {
        // Data is already hardcoded in the controller.
        // In a real app you would seed the database here.
    }

    @State("User with ID 2 exists")
    void userWithId2Exists() {
        // Data is already hardcoded in the controller.
        // In a real app you would seed the database here.
    }
}
