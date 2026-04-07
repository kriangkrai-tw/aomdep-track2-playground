# Pact Consumer-Driven Contract Testing POC

A working proof-of-concept for **Consumer-Driven Contract Testing (CDCT)** using [Pact JVM 4.6](https://docs.pact.io/), [Spring Boot 3.2](https://spring.io/projects/spring-boot), and a self-hosted [Pact Broker](https://docs.pact.io/pact_broker).

---

## Table of Contents

1. [What is Consumer-Driven Contract Testing?](#1-what-is-consumer-driven-contract-testing)
2. [Why Pact?](#2-why-pact)
3. [How it works — the full flow](#3-how-it-works--the-full-flow)
4. [Project structure](#4-project-structure)
5. [Prerequisites](#5-prerequisites)
6. [Running the POC end-to-end](#6-running-the-poc-end-to-end)
7. [Code walkthrough](#7-code-walkthrough)
8. [The Pact file explained](#8-the-pact-file-explained)
9. [The Pact Broker explained](#9-the-pact-broker-explained)
10. [What happens if the contract breaks?](#10-what-happens-if-the-contract-breaks)
11. [Running without the Pact Broker](#11-running-without-the-pact-broker)
12. [CI/CD integration](#12-cicd-integration)

---

## 1. What is Consumer-Driven Contract Testing?

In a microservices architecture two services interact over HTTP:

- The **Consumer** is the service that *calls* an API (here: `OrderService` calling `UserService`).
- The **Provider** is the service that *serves* the API (here: `UserService`).

**The problem** with traditional integration testing is that both services must be running at the same time. This is slow, fragile, and makes it hard to tell *who* broke what.

**Consumer-Driven Contract Testing** solves this by letting the consumer define a *contract* — a document that describes exactly what it needs from the provider. The provider then independently verifies it can satisfy that contract, with no live consumer needed.

```
Traditional approach:               Pact approach:
                                  
OrderService ──live HTTP──► UserService     OrderService ──generates──► contract file
(must both be running)                      UserService  ──verifies──► contract file
                                            (independent, fast, no network)
```

---

## 2. Why Pact?

Pact automates the creation and verification of contracts:

| Feature | Benefit |
|---|---|
| Consumer writes the test | Contract reflects what the consumer *actually needs*, not what the provider *assumes* |
| Pact generates the contract | No manual JSON writing; the test code is the source of truth |
| Matching rules (not exact values) | Provider can return `"Bob"` where consumer expected `"Alice"` — as long as it's a string, the contract passes |
| Pact Broker | Central store for contracts; tracks which versions have been verified |
| `can-i-deploy` | Before releasing, check whether all contracts are satisfied — safe deployments |

---

## 3. How it Works — the Full Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 1: Consumer test (order-service)                              │
│                                                                     │
│  UserClientPactTest                                                 │
│  ┌─────────────────────┐       ┌──────────────────────┐            │
│  │  @Pact method        │──────►│  Pact Mock Server    │            │
│  │  defines expected    │       │  (started by JUnit   │            │
│  │  request & response  │       │   extension)         │            │
│  └─────────────────────┘       └──────────┬───────────┘            │
│                                            │ UserClient calls it    │
│  @Test asserts consumer                    │                        │
│  code handles the response ◄───────────────┘                       │
│                                                                     │
│  On success: OrderService-UserService.json written to target/pacts/ │
└─────────────────────────────────────────────────────────────────────┘
                        │
                        │  mvn pact:publish
                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 2: Pact Broker (localhost:9292)                               │
│                                                                     │
│  Stores the contract JSON, tags it with version + branch, and      │
│  serves it to any provider that wants to verify against it.        │
└─────────────────────────────────────────────────────────────────────┘
                        │
                        │  provider fetches pact during mvn test
                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STEP 3: Provider verification (user-service)                       │
│                                                                     │
│  UserServicePactVerificationTest                                    │
│  ┌──────────────────────┐      ┌──────────────────────────┐        │
│  │  @PactBroker fetches  │      │  Spring MockMvc           │        │
│  │  contract from broker │─────►│  replays each interaction │        │
│  └──────────────────────┘      │  against UserController   │        │
│                                 └───────────┬──────────────┘        │
│  Pact checks: status, body                  │                       │
│  fields, matching rules ◄───────────────────┘                      │
│                                                                     │
│  On success: verification result published back to broker ✅        │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Project Structure

```
pact-poc/
├── docker-compose.yml                          # Pact Broker + Postgres
│
├── order-service/                              # CONSUMER
│   ├── pom.xml
│   └── src/
│       ├── main/java/com/example/orderservice/
│       │   ├── OrderServiceApplication.java
│       │   └── client/
│       │       └── UserClient.java             # The HTTP client under test
│       └── test/java/com/example/orderservice/
│           └── contract/
│               └── UserClientPactTest.java     # Generates the pact contract
│
└── user-service/                               # PROVIDER
    ├── pom.xml
    └── src/
        ├── main/java/com/example/userservice/
        │   ├── UserServiceApplication.java
        │   └── controller/
        │       └── UserController.java         # The REST controller being verified
        └── test/java/com/example/userservice/
            └── contract/
                └── UserServicePactVerificationTest.java  # Verifies the contract
```

---

## 5. Prerequisites

| Tool | Version used | Notes |
|---|---|---|
| Java | 17 | |
| Maven | 3.9+ | `brew install maven` |
| Docker | any | To run the Pact Broker |

---

## 6. Running the POC End-to-End

### Step 1 — Start the Pact Broker

```bash
docker-compose up -d
```

This starts two containers:
- **postgres** — database backend for the broker
- **pact-broker** — the broker web UI and API

Open the broker UI: http://localhost:9292

### Step 2 — Run the consumer test (OrderService)

```bash
cd order-service
mvn test
```

What happens:
1. JUnit 5 starts and the `@ExtendWith(PactConsumerTestExt.class)` extension is activated.
2. The `@Pact`-annotated method `getUserById()` registers an expected interaction with a Pact-managed **mock server** (started on a random port).
3. The `@Test` method creates a real `UserClient` pointed at the mock server and calls `getUserById(1)`.
4. Pact intercepts the HTTP request, matches it against the defined interaction, and returns the mocked response.
5. Assertions verify that `UserClient` correctly parses the response.
6. On success, Pact writes `target/pacts/OrderService-UserService.json`.

### Step 3 — Publish the pact to the broker

```bash
mvn pact:publish
```

This uploads `OrderService-UserService.json` to the broker at `http://localhost:9292`, tagged as version `1.0.0` on the `main` branch.

You can now see it in the broker UI at http://localhost:9292.

### Step 4 — Run the provider verification (UserService)

```bash
cd ../user-service
mvn test
```

What happens:
1. Spring Boot's `@WebMvcTest` starts a lightweight test application context with only `UserController` loaded.
2. `@PactBroker` tells Pact to fetch all pacts for provider `"UserService"` from `localhost:9292`.
3. For each interaction in the pact, Pact calls the `@State` method to set up the required test data (here it's a no-op since data is hardcoded).
4. Pact replays the recorded HTTP request through `MockMvc` against `UserController`.
5. Pact checks the response matches the contract: correct status code, required fields present, and matching rules satisfied.
6. The verification result (pass/fail) is **published back to the broker** (`pact.verifier.publishResults=true`).

---

## 7. Code Walkthrough

### Consumer test — `UserClientPactTest.java`

```java
@ExtendWith(PactConsumerTestExt.class)          // Activates the Pact JUnit 5 extension
@PactTestFor(providerName = "UserService",       // Names the provider in the contract
             pactVersion = PactSpecVersion.V3)   // Use Pact spec v3
class UserClientPactTest {

    // Defines the contract: "given this state, when I send this request,
    // I expect this response"
    @Pact(consumer = "OrderService", provider = "UserService")
    public RequestResponsePact getUserById(PactDslWithProvider builder) {
        return builder
            .given("User with ID 1 exists")          // Provider state — tells the provider
                                                      // what data to have ready
            .uponReceiving("a request for User 1 details")
                .path("/users/1")
                .method("GET")
            .willRespondWith()
                .status(200)
                .body(LambdaDsl.newJsonBody(body -> {
                    body.numberType("id", 1);         // Matching rule: must be a number
                    body.stringType("name", "Alice"); // Matching rule: must be a string
                    body.stringType("email", "alice@example.com");
                }).build())
            .toPact();
    }

    // Runs the actual consumer code against the Pact mock server
    @Test
    @PactTestFor(pactMethod = "getUserById")          // Links test to the @Pact method
    void testGetUserById(MockServer mockServer) {     // Pact injects the mock server URL
        UserClient client = new UserClient(mockServer.getUrl());

        Map<String, Object> user = client.getUserById(1);

        // Verify the consumer correctly handles the response
        assertThat(user).containsKey("id");
        assertThat(user.get("name")).isEqualTo("Alice");
        assertThat(user.get("email")).isEqualTo("alice@example.com");
    }
}
```

**Key point:** the `@Pact` method uses **matching rules**, not exact values. `body.stringType("name", "Alice")` means: *the field `name` must exist and be a string* — the actual value `"Alice"` is only the example used in the mock response and in the pact file.

---

### The HTTP client — `UserClient.java`

```java
public class UserClient {
    private final WebClient webClient;

    public UserClient(String baseUrl) {
        this.webClient = WebClient.builder().baseUrl(baseUrl).build();
    }

    public Map<String, Object> getUserById(int userId) {
        return webClient.get()
                .uri("/users/{id}", userId)
                .retrieve()
                .bodyToMono(Map.class)
                .map(m -> (Map<String, Object>) m)
                .block();
    }
}
```

This is the real production code. In the consumer test it is pointed at the Pact mock server. In production it is pointed at the real `UserService` URL.

---

### Provider verification test — `UserServicePactVerificationTest.java`

```java
@WebMvcTest(UserController.class)               // Lightweight Spring context — only the controller
@Provider("UserService")                        // Must match the provider name in the pact
@PactBroker(                                    // Fetch pacts from the broker
    host = "${pactbroker.host:localhost}",       // Configurable via system property
    port = "${pactbroker.port:9292}"
)
@ExtendWith(PactVerificationInvocationContextProvider.class)
class UserServicePactVerificationTest {

    @Autowired
    private MockMvc mockMvc;

    @BeforeEach
    void setUp(PactVerificationContext context) {
        // Tell Pact to use MockMvc as the HTTP target (no real server needed)
        context.setTarget(new MockMvcTestTarget(mockMvc));
    }

    // Pact generates one test per interaction found in the broker
    @TestTemplate
    void verifyPact(PactVerificationContext context) {
        context.verifyInteraction();
    }

    // Called before each interaction that requires this provider state
    @State("User with ID 1 exists")
    void userWithId1Exists() {
        // In a real app: insert a test user into the database here.
        // Here the controller has hardcoded data so no setup is needed.
    }
}
```

**Key point:** `@TestTemplate` is not a regular `@Test` — Pact uses JUnit 5's test template mechanism to dynamically generate one test case per interaction pulled from the broker. You don't write the test body; Pact drives it.

---

### Provider REST controller — `UserController.java`

```java
@RestController
@RequestMapping("/users")
public class UserController {

    @GetMapping("/{id}")
    public ResponseEntity<?> getUser(@PathVariable int id) {
        if (id == 1) {
            return ResponseEntity.ok(Map.of(
                    "id", 1,
                    "name", "Alice",
                    "email", "alice@example.com"
            ));
        }
        return ResponseEntity.notFound().build();
    }
}
```

This is pure production code. It has no knowledge of Pact. The verification test drives it through Spring MockMvc.

---

## 8. The Pact File Explained

After running `mvn test` in `order-service`, a file is created at `target/pacts/OrderService-UserService.json`:

```json
{
  "consumer": { "name": "OrderService" },
  "provider": { "name": "UserService" },
  "interactions": [
    {
      "description": "a request for User 1 details",
      "providerStates": [{ "name": "User with ID 1 exists" }],
      "request": {
        "method": "GET",
        "path": "/users/1"
      },
      "response": {
        "status": 200,
        "headers": {
          "Content-Type": "application/json; charset=UTF-8"
        },
        "body": {
          "id": 1,
          "name": "Alice",
          "email": "alice@example.com"
        },
        "matchingRules": {
          "body": {
            "$.id":    { "matchers": [{ "match": "number" }] },
            "$.name":  { "matchers": [{ "match": "type" }] },
            "$.email": { "matchers": [{ "match": "type" }] }
          }
        }
      }
    }
  ],
  "metadata": {
    "pactSpecification": { "version": "3.0.0" },
    "pact-jvm": { "version": "4.6.16" }
  }
}
```

**Sections:**
- `consumer` / `provider` — the two parties in the contract.
- `interactions` — the list of recorded request/response pairs. Each is a separate verifiable test.
- `providerStates` — instructions to the provider about what data must exist before this request is made.
- `matchingRules` — tells the verifier to check *type* rather than exact value. `"match": "type"` means "any string is fine"; `"match": "number"` means "any number is fine".

---

## 9. The Pact Broker Explained

The Pact Broker (`docker-compose.yml`) is a central service that:

- **Stores pact files** uploaded by consumers.
- **Stores verification results** published by providers.
- **Tracks relationships** between consumer and provider versions.
- **Provides `can-i-deploy`** — a query that answers "is it safe to deploy consumer version X with provider version Y?"

```
                ┌────────────────────────────────┐
  consumer      │         Pact Broker             │      provider
  mvn pact:     │  ┌──────────────────────────┐  │      mvn test
  publish  ────►│  │  OrderService (1.0.0)     │  │◄────  fetches pact
                │  │  └─► pact with UserService│  │       verifies it
                │  │      verified ✅ by 1.0.0  │  │       publishes result
                │  └──────────────────────────┘  │
                └────────────────────────────────┘
                       http://localhost:9292
```

Open http://localhost:9292 to see the matrix view showing which consumer/provider version combinations have been verified.

---

## 10. What Happens if the Contract Breaks?

### Scenario A — Provider removes a field

If `UserController` stopped returning `email`:

```java
return ResponseEntity.ok(Map.of("id", 1, "name", "Alice")); // email removed
```

Then `mvn test` in `user-service` would fail:

```
FAILED - a request for User 1 details
  Body had differences:
    $.email -> Expected 'alice@example.com' but was missing
```

The provider CI pipeline fails. The provider team is alerted *before* they deploy. The consumer is never affected.

### Scenario B — Consumer needs a new field

If `OrderService` now also needs `phone`, the consumer adds it to the pact:

```java
body.stringType("phone", "555-1234");
```

The consumer test passes (mock server provides the new field). The pact is published. Then `user-service` runs verification and it **fails** — because `UserController` doesn't return `phone` yet.

This is the correct outcome: the consumer has communicated a new requirement to the provider team via the broker.

---

## 11. Running Without the Pact Broker

To run the provider test against a local pact file (no Docker needed), replace `@PactBroker` in `UserServicePactVerificationTest.java` with:

```java
import au.com.dius.pact.provider.junitsupport.loader.PactFolder;

@PactFolder("../order-service/target/pacts")
```

Then run `mvn test` from `user-service/` directly.

---

## 12. CI/CD Integration

A typical pipeline for two services looks like this:

```
OrderService CI:                         UserService CI:
───────────────                          ───────────────
1. mvn test                              1. mvn test
   (consumer test runs,                     (fetches pact from broker,
    pact file generated)                     verifies UserController,
2. mvn pact:publish                          publishes result to broker)
   (upload to broker)
3. can-i-deploy check
   (safe to deploy?)
```

The `can-i-deploy` check (via the [Pact CLI](https://docs.pact.io/pact_broker/can_i_deploy)) ensures a consumer version is only deployed if the provider has a verified, deployed version that satisfies its pact:

```bash
pact-broker can-i-deploy \
  --pacticipant OrderService --version 1.0.0 \
  --pacticipant UserService --latest \
  --broker-base-url http://localhost:9292
```

