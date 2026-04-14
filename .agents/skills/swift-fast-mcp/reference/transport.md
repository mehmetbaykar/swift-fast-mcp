# Transport Options

## Transport Enum

```swift
public enum Transport: Sendable {
  case stdio
  case inMemory
  case http(
    mode: HTTPMode = .stateful,
    host: String = "127.0.0.1",
    port: Int = 3000,
    endpoint: String = "/mcp"
  )
  case custom(MCP.Transport)
}
```

## HTTPMode Enum

```swift
public enum HTTPMode: Sendable {
  case stateful
  case stateless
}
```

- `stateful`: session-aware Streamable HTTP with session IDs, SSE streaming, GET/DELETE support
- `stateless`: POST-only JSON request/response without session tracking

## .stdio (Default)

Standard I/O transport. Reads from stdin, writes to stdout. Used for CLI tools and Claude Desktop.

```swift
try await FastMCP.builder()
  .transport(.stdio)
  .run()
```

## .http()

HTTP transport with stateful or stateless modes.

```swift
try await FastMCP.builder()
  .name("MyServer")
  .addTools([StructuredSearchTool()])
  .transport(.http(mode: .stateful, host: "127.0.0.1", port: 8080, endpoint: "/mcp"))
  .run()
```

All parameters have defaults, so `.http()` alone works:

```swift
try await FastMCP.builder()
  .transport(.http())
  .run()
```

### Stateful HTTP

```swift
try await FastMCP.builder()
  .transport(.http(mode: .stateful, port: 8080))
  .sessionTimeout(.seconds(300))
  .run()
```

Each client gets its own `Server` + transport session. The session ID is returned in the
`Mcp-Session-Id` header.

### Stateless HTTP

```swift
try await FastMCP.builder()
  .transport(.http(mode: .stateless, port: 9090))
  .run()
```

Each request is independent. No session tracking.

### HTTP Validation

Use `.httpValidation()` to control allowed origins and add custom validators:

```swift
try await FastMCP.builder()
  .transport(.http(port: 8080))
  .httpValidation(
    allowedOrigins: ["https://example.com"],
    customValidators: [BearerTokenValidator(expectedToken: "...")]
  )
  .run()
```

`customValidators` conform to `HTTPRequestValidator` from the MCP SDK.

## .inMemory

In-memory transport with no I/O. Useful for tests.

```swift
try await FastMCP.builder()
  .transport(.inMemory)
  .run()
```

## .custom(MCP.Transport)

Inject any custom transport that conforms to `MCP.Transport`:

```swift
let myTransport: MCP.Transport = ...

try await FastMCP.builder()
  .transport(.custom(myTransport))
  .run()
```

## Setting Transport

```swift
let builder = FastMCP.builder()
  .transport(.stdio)
```

Calling `.transport()` again replaces the previous value.
