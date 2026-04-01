# Todo Service API Documentation

**Base URL:** `http://localhost:8080`  
**Content-Type:** `application/json`

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/todos` | List all todos |
| `GET` | `/api/todos/{id}` | Get a todo by ID |
| `POST` | `/api/todos` | Create a new todo |
| `PUT` | `/api/todos/{id}` | Update a todo |
| `PATCH` | `/api/todos/{id}/complete` | Mark a todo as complete |
| `DELETE` | `/api/todos/{id}` | Delete a todo |

---

## Data Model

All successful responses return a `TodoResponse` object:

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier (auto-generated) |
| `title` | String | Todo title (max 255 characters) |
| `description` | String | Optional description text |
| `completed` | Boolean | Completion status (default: `false`) |
| `createdAt` | ISO-8601 datetime | Creation timestamp (auto-set) |
| `updatedAt` | ISO-8601 datetime | Last updated timestamp (auto-set) |

---

## Endpoints

### GET /api/todos — List all todos

Returns a list of all todos. Optionally filter by completion status.

**Query Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `completed` | Boolean | No | Filter by completion status (`true` or `false`) |

**Response — 200 OK**
```json
[
  {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Buy groceries",
    "description": "Milk, eggs, bread",
    "completed": false,
    "createdAt": "2024-04-01T10:30:00",
    "updatedAt": "2024-04-01T10:30:00"
  }
]
```

**curl**
```bash
# Get all todos
curl http://localhost:8080/api/todos

# Filter by completed
curl "http://localhost:8080/api/todos?completed=true"

# Filter by incomplete
curl "http://localhost:8080/api/todos?completed=false"
```

---

### GET /api/todos/{id} — Get a todo by ID

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | UUID | Yes | The todo ID |

**Response — 200 OK**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Buy groceries",
  "description": "Milk, eggs, bread",
  "completed": false,
  "createdAt": "2024-04-01T10:30:00",
  "updatedAt": "2024-04-01T10:30:00"
}
```

**Response — 404 Not Found**
```json
{
  "type": "about:blank",
  "title": "Not Found",
  "status": 404,
  "detail": "Todo not found with id: 550e8400-e29b-41d4-a716-446655440000"
}
```

**curl**
```bash
curl http://localhost:8080/api/todos/550e8400-e29b-41d4-a716-446655440000
```

---

### POST /api/todos — Create a todo

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | String | Yes | Must not be blank, max 255 characters |
| `description` | String | No | Free-form description text |

```json
{
  "title": "Buy groceries",
  "description": "Milk, eggs, bread"
}
```

**Response — 201 Created**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Buy groceries",
  "description": "Milk, eggs, bread",
  "completed": false,
  "createdAt": "2024-04-01T10:30:00",
  "updatedAt": "2024-04-01T10:30:00"
}
```

**Response — 400 Bad Request** (validation failure)
```json
{
  "type": "about:blank",
  "title": "Bad Request",
  "status": 400,
  "detail": "Validation failed",
  "errors": {
    "title": "Title must not be blank"
  }
}
```

**curl**
```bash
# With title and description
curl -X POST http://localhost:8080/api/todos \
  -H "Content-Type: application/json" \
  -d '{"title": "Buy groceries", "description": "Milk, eggs, bread"}'

# Title only
curl -X POST http://localhost:8080/api/todos \
  -H "Content-Type: application/json" \
  -d '{"title": "Call dentist"}'
```

---

### PUT /api/todos/{id} — Update a todo

All fields are optional. Only the fields provided will be updated.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | UUID | Yes | The todo ID |

**Request Body**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | String | No | Max 255 characters |
| `description` | String | No | Free-form description text |
| `completed` | Boolean | No | Completion status |

```json
{
  "title": "Buy groceries and cook dinner",
  "description": "Updated description",
  "completed": true
}
```

**Response — 200 OK**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Buy groceries and cook dinner",
  "description": "Updated description",
  "completed": true,
  "createdAt": "2024-04-01T10:30:00",
  "updatedAt": "2024-04-01T11:45:00"
}
```

**Response — 404 Not Found**
```json
{
  "type": "about:blank",
  "title": "Not Found",
  "status": 404,
  "detail": "Todo not found with id: 550e8400-e29b-41d4-a716-446655440000"
}
```

**curl**
```bash
# Update all fields
curl -X PUT http://localhost:8080/api/todos/550e8400-e29b-41d4-a716-446655440000 \
  -H "Content-Type: application/json" \
  -d '{"title": "Buy groceries and cook dinner", "description": "Updated description", "completed": true}'

# Mark as complete only
curl -X PUT http://localhost:8080/api/todos/550e8400-e29b-41d4-a716-446655440000 \
  -H "Content-Type: application/json" \
  -d '{"completed": true}'

# Update title only
curl -X PUT http://localhost:8080/api/todos/550e8400-e29b-41d4-a716-446655440000 \
  -H "Content-Type: application/json" \
  -d '{"title": "New title"}'
```

---

### PATCH /api/todos/{id}/complete — Mark a todo as complete

Sets the `completed` field to `true`.

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | UUID | Yes | The todo ID |

**Request Body:** None

**Response — 200 OK**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Buy groceries",
  "description": "Milk, eggs, bread",
  "completed": true,
  "createdAt": "2024-04-01T10:30:00",
  "updatedAt": "2024-04-01T11:45:00"
}
```

**Response — 404 Not Found**
```json
{
  "type": "about:blank",
  "title": "Not Found",
  "status": 404,
  "detail": "Todo not found with id: 550e8400-e29b-41d4-a716-446655440000"
}
```

**curl**
```bash
curl -X PATCH http://localhost:8080/api/todos/550e8400-e29b-41d4-a716-446655440000/complete
```

---

### DELETE /api/todos/{id} — Delete a todo

**Path Parameters**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | UUID | Yes | The todo ID |

**Response — 204 No Content:** Empty body

**Response — 404 Not Found**
```json
{
  "type": "about:blank",
  "title": "Not Found",
  "status": 404,
  "detail": "Todo not found with id: 550e8400-e29b-41d4-a716-446655440000"
}
```

**curl**
```bash
curl -X DELETE http://localhost:8080/api/todos/550e8400-e29b-41d4-a716-446655440000
```

---

## Error Responses

All errors follow the [RFC 7807 Problem Details](https://www.rfc-editor.org/rfc/rfc7807) format:

```json
{
  "type": "about:blank",
  "title": "<HTTP status text>",
  "status": <HTTP status code>,
  "detail": "<human-readable description>"
}
```

| Status | Cause |
|--------|-------|
| `400 Bad Request` | Request body failed validation (e.g., missing required `title`) |
| `404 Not Found` | Todo with the given ID does not exist |

---

## Health & Monitoring

Spring Boot Actuator endpoints are available:

```bash
# Service health
curl http://localhost:8080/actuator/health

# Application info
curl http://localhost:8080/actuator/info

# Metrics
curl http://localhost:8080/actuator/metrics
```
