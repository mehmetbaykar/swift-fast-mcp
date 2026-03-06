# Transport Options

## Transport Enum

```swift
public enum Transport: Sendable {
  case stdio
  case inMemory
  case custom(MCP.Transport)
}
```

## .stdio (Default)

Standard I/O transport. Reads from stdin, writes to stdout. Used for CLI tools and Claude Desktop integration.

```swift
try await FastMCP.builder()
  .transport(.stdio)  // This is the default, can be omitted
  .run()
```

Internally creates `StdioTransport(logger:)`.

**When to use**: Production MCP servers, Claude Desktop integration, any CLI-based MCP server.

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
let myTransport: MCP.Transport = // your custom transport
try await FastMCP.builder()
  .transport(.custom(myTransport))
  .run()
```

**When to use**: Custom networking (HTTP/SSE, WebSocket), testing with mock transports, or any transport not built into FastMCP.

## Setting Transport

```swift
let builder = FastMCP.builder()
  .transport(.stdio)  // or .inMemory, or .custom(...)
```

The transport is set once. Calling `.transport()` again replaces the previous value.
