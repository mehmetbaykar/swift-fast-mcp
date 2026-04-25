# Transports

Source of truth: `Sources/swift-fast-mcp/Transport.swift` and
`Sources/swift-fast-mcp/FastMCP.swift`.

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

`HTTPMode` is `.stateful` or `.stateless`. Configure HTTP request validation
through `FastMCP.builder().httpValidation(allowedOrigins:customValidators:)`;
the builder applies that pipeline only for `.http(...)`.

See [`docs/Transports.md`](../../../../docs/Transports.md) for runtime
behavior and the `ServiceGroup` lifecycle.
