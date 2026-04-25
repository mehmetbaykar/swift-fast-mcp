# FastMCP Builder API Reference

Every method on `FastMCP.Builder` returns a new copy (value semantics) and
can be chained. Source of truth:
[`Sources/swift-fast-mcp/FastMCP.swift`](../../../../Sources/swift-fast-mcp/FastMCP.swift).
Dynamic catalogue methods live in
[`Sources/swift-fast-mcp/ServerHandle.swift`](../../../../Sources/swift-fast-mcp/ServerHandle.swift).
Transport cases live in
[`Sources/swift-fast-mcp/Transport.swift`](../../../../Sources/swift-fast-mcp/Transport.swift).

## Construction

```swift
let builder = FastMCP.builder()
```

## Methods

| Method | Signature | Default |
|---|---|---|
| `name` | `func name(_ name: String) -> Builder` | `ProcessInfo.processInfo.processName` |
| `version` | `func version(_ version: String) -> Builder` | `"1.0.0"` |
| `title` | `func title(_ title: String) -> Builder` | `nil` |
| `instructions` | `func instructions(_ instructions: String) -> Builder` | `nil` |
| `icons` | `func icons(_ icons: [Icon]) -> Builder` | `nil` |
| `addTools` | `func addTools(_ newTools: [any SwiftAIHub.Tool]) throws -> Builder` | `[]` |
| `addResources` | `func addResources(_ newResources: [any MCPResource]) -> Builder` | `[]` |
| `addPrompts` | `func addPrompts(_ newPrompts: [any MCPPrompt]) -> Builder` | `[]` |
| `enableCompletions` | `func enableCompletions(_ enabled: Bool = true) -> Builder` | `false` |
| `enableLogging` | `func enableLogging(_ enabled: Bool = true) -> Builder` | `false` |
| `transport` | `func transport(_ transport: Transport) -> Builder` | `.stdio` |
| `logger` | `func logger(_ logger: Logger) -> Builder` | auto from `name` |
| `shutdownSignals` | `func shutdownSignals(_ signals: [UnixSignal]) -> Builder` | `[.sigterm, .sigint]` |
| `onStart` | `func onStart(_ handler: @escaping @Sendable () async -> Void) -> Builder` | `nil` |
| `onShutdown` | `func onShutdown(_ handler: @escaping @Sendable () async -> Void) -> Builder` | `nil` |
| `onInitialize` | `func onInitialize(_ handler: @escaping @Sendable (Client.Info, Client.Capabilities) async throws -> Void) -> Builder` | `nil` |
| `sessionTimeout` | `func sessionTimeout(_ timeout: Duration) -> Builder` | `.seconds(3600)` |
| `httpValidation` | `func httpValidation(allowedOrigins: [String]? = nil, customValidators: [any HTTPRequestValidator] = []) -> Builder` | no overrides |
| `serverHandle` | `func serverHandle(_ handle: FastMCPServerHandle) -> Builder` | `nil` |
| `run` | `func run() async throws` | — |

`addTools` is `throws` and rejects duplicate tool names eagerly with
`HubBridgeError.duplicateTool(name:)` (`FastMCP.swift:80`). The other
`add…` methods are non-throwing and silently drop duplicates (resources by
`uri`, prompts by `name`).

Generated server packages depend on `swift-fast-mcp` from `"2.3.0"`.
FastMCP's own `Package.swift` declares swift-ai-hub from `"0.1.0"` using
product `SwiftAIHub` from package `swift-ai-hub`, and
`Sources/swift-fast-mcp/Exports.swift` re-exports it through `import FastMCP`.
`MCP` itself is not re-exported; add `import MCP` when naming MCP SDK types
such as `Icon`, `Client.Info`, `Client.Capabilities`, `HTTPRequestValidator`,
or a custom `MCP.Transport`.

## `run()` execution order

1. Resolve the logger (custom or one labelled with the server name).
2. Log a warning when no tools, resources, prompts, or handle are registered.
3. Build server capabilities (`listChanged: true` when a handle is attached).
4. Seed the handle with the initial catalogue when present.
5. For HTTP transports, build a per-session factory with a validation
   pipeline from `httpValidation`; for stdio / in-memory / custom, build one `Server`.
6. Register tools, resources, and prompts on the server(s).
7. Start the transport inside a `swift-service-lifecycle` `ServiceGroup`
   with the configured shutdown signals.
8. `onInitialize` runs whenever a client sends `initialize`; `onStart` runs
   when the service starts; `onShutdown` runs on graceful shutdown.

## Kitchen-Sink Example

```swift
import FastMCP

let logger: Logger = {
  var log = Logger(label: "MyServer")
  log.logLevel = .info
  return log
}()

try await FastMCP.builder()
  .name("MyServer")
  .version("1.0.0")
  .title("My MCP Server")
  .instructions("A full-featured MCP server")
  .addTools([
    WeatherTool(),
    StructuredSearchTool(),
    GreetingTool(),
  ])
  .addResources([
    ConfigResource(),
    SystemInfoResource(),
  ])
  .addPrompts([
    GreetingPrompt(),
    CodeReviewPrompt(),
  ])
  .enableCompletions()
  .enableLogging()
  .transport(.http(mode: .stateful, host: "127.0.0.1", port: 8080, endpoint: "/mcp"))
  .sessionTimeout(.seconds(300))
  .httpValidation(
    allowedOrigins: ["https://example.com"],
    customValidators: [MyAuthValidator()]
  )
  .logger(logger)
  .shutdownSignals([.sigterm, .sigint])
  .onInitialize { clientInfo, _ in
    logger.info("Client initialized: \(clientInfo.name)")
  }
  .onStart { logger.info("Server started") }
  .onShutdown { logger.info("Server shutting down") }
  .run()
```

## Logger

`logger(_:)` overrides the default. When omitted, the builder creates
`Logger(label: serverName)`. `import FastMCP` re-exports `Logging` so
`Logger` is available without a separate import. Under `.stdio`, do not
`print` from hooks — stdout carries JSON-RPC frames; route messages
through the logger.

## Accumulation

`addTools`, `addResources`, and `addPrompts` can be called multiple times.
Items accumulate across calls, with the deduplication rules above.

## Dynamic catalogue with `FastMCPServerHandle`

Attach a handle to mutate tools, resources, or prompts after `run()` starts.
When attached, `listChanged: true` is advertised on every capability and
clients receive `notifications/{tools,resources,prompts}/list_changed`.

```swift
let handle = FastMCPServerHandle()

Task {
  try await FastMCP.builder()
    .name("DynamicServer")
    .addTools([WeatherTool()])
    .serverHandle(handle)
    .run()
}

try await handle.addTool(MathTool())
await handle.removeTool(named: "weather")
await handle.addResource(ConfigResource())
await handle.addPrompt(GreetingPrompt())
```

See [`docs/DynamicServers.md`](../../../../docs/DynamicServers.md) for the
per-session HTTP flow and concurrency guarantees, and
[`docs/Transports.md`](../../../../docs/Transports.md) for transport
selection.
