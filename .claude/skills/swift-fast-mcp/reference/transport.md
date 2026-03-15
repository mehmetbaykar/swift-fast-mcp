# Transport Options

## Transport Enum

```swift
public enum Transport: Sendable {
  case stdio
  case http(mode: HTTPMode = .stateful, host: String = "127.0.0.1", port: Int = 8080, endpoint: String = "/mcp")
  case inMemory
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

- **stateful**: Multi-session support, SSE streaming, session management via `Mcp-Session-Id` header. Clients open an SSE connection and receive streamed responses. Sessions are tracked and can be timed out with `.sessionTimeout()`.
- **stateless**: JSON request/response, no sessions. Each request is independent. Suitable for simple integrations and serverless environments.

## .stdio (Default)

Standard I/O transport. Reads from stdin, writes to stdout. Used for CLI tools and Claude Desktop integration.

```swift
try await FastMCP.builder()
  .transport(.stdio)
  .run()
```

Internally creates `StdioTransport(logger:)`.

**When to use**: Production MCP servers, Claude Desktop integration, any CLI-based MCP server.

## .http()

HTTP transport with SSE or JSON modes. Binds to a host and port.

```swift
try await FastMCP.builder()
  .name("MyServer")
  .addTools([WeatherTool()])
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

Clients connect via SSE. The server assigns a `Mcp-Session-Id` header. Multiple concurrent sessions are supported. Sessions expire after the configured timeout.

### Stateless HTTP

```swift
try await FastMCP.builder()
  .transport(.http(mode: .stateless, port: 9090))
  .run()
```

Each request is a standalone JSON request/response cycle. No session tracking.

### HTTP Validation

```swift
try await FastMCP.builder()
  .transport(.http(port: 8080))
  .httpValidation { request in
    request.headerFields.contains(.authorization)
  }
  .run()
```

**When to use**: Web-based MCP clients, multi-session servers, remote access, Linux deployments.

## .inMemory

In-memory transport with no I/O. Used for testing.

```swift
try await FastMCP.builder()
  .transport(.inMemory)
  .run()
```

Internally creates `InMemoryTransport()`.

**When to use**: Unit tests, integration tests, verifying server configuration without actual I/O.

## .custom(MCP.Transport)

Inject any custom transport that conforms to `MCP.Transport`:

```swift
let myTransport: MCP.Transport = ...
try await FastMCP.builder()
  .transport(.custom(myTransport))
  .run()
```

**When to use**: Custom networking, testing with mock transports, or any transport not built into FastMCP.

## Setting Transport

```swift
let builder = FastMCP.builder()
  .transport(.stdio)  // or .http(), .inMemory, .custom(...)
```

The transport is set once. Calling `.transport()` again replaces the previous value.
