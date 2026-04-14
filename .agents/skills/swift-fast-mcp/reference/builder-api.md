# FastMCP Builder API Reference

## Creating a Builder

```swift
let builder = FastMCP.builder()
```

Returns a `FastMCP.Builder` struct. All methods return a new copy (value semantics).

## Methods

| Method | Signature | Default |
|--------|-----------|---------|
| `name()` | `func name(_ name: String) -> Builder` | `ProcessInfo.processInfo.processName` |
| `version()` | `func version(_ version: String) -> Builder` | `"1.0.0"` |
| `title()` | `func title(_ title: String) -> Builder` | `nil` |
| `instructions()` | `func instructions(_ instructions: String) -> Builder` | `nil` |
| `icons()` | `func icons(_ icons: [Icon]) -> Builder` | `nil` |
| `addTools()` | `func addTools(_ newTools: [any MCPTool]) -> Builder` | `[]` |
| `addResources()` | `func addResources(_ newResources: [any MCPResource]) -> Builder` | `[]` |
| `addPrompts()` | `func addPrompts(_ newPrompts: [any MCPPrompt]) -> Builder` | `[]` |
| `enableCompletions()` | `func enableCompletions(_ enabled: Bool = true) -> Builder` | `false` |
| `enableLogging()` | `func enableLogging(_ enabled: Bool = true) -> Builder` | `false` |
| `transport()` | `func transport(_ transport: Transport) -> Builder` | `.stdio` |
| `logger()` | `func logger(_ logger: Logger) -> Builder` | `nil` |
| `shutdownSignals()` | `func shutdownSignals(_ signals: [UnixSignal]) -> Builder` | `[.sigterm, .sigint]` |
| `onStart()` | `func onStart(_ handler: @escaping @Sendable () async -> Void) -> Builder` | `nil` |
| `onShutdown()` | `func onShutdown(_ handler: @escaping @Sendable () async -> Void) -> Builder` | `nil` |
| `onInitialize()` | `func onInitialize(_ handler: @escaping @Sendable (Client.Info, Client.Capabilities) async throws -> Void) -> Builder` | `nil` |
| `sessionTimeout()` | `func sessionTimeout(_ timeout: Duration) -> Builder` | `.seconds(3600)` |
| `httpValidation()` | `func httpValidation(allowedOrigins: [String]? = nil, customValidators: [any HTTPRequestValidator] = []) -> Builder` | no overrides |
| `serverHandle()` | `func serverHandle(_ handle: FastMCPServerHandle) -> Builder` | `nil` |
| `run()` | `func run() async throws` | -- |

## Value Semantics

Each method returns a new `Builder` copy. The original is not modified:

```swift
let base = FastMCP.builder().name("Base")
let modified = base.name("Modified")
// base.serverName == "Base"
// modified.serverName == "Modified"
```

## Structured Tools

`addTools()` accepts `[any MCPTool]`, so `MCPStructuredTool` works automatically because it
inherits from `MCPTool`.

```swift
let builder = FastMCP.builder()
  .addTools([
    GreetingTool(),
    StructuredSearchTool(),
  ])
```

Structured tools publish `outputSchema` through the toolkit; the builder does not need any
special configuration for them.

## Execution Order

When `run()` is called:

1. Logger is created (custom or auto from server name)
2. Warning is logged if no tools, resources, or prompts are registered and no handle is attached
3. Server capabilities are built from the registered components
4. If a `FastMCPServerHandle` is attached, it is seeded with the initial tools/resources/prompts
5. A `Server` is created with name, version, metadata, and capabilities
6. Tools, resources, and prompts are registered on the server
7. The selected transport starts
8. `onInitialize` runs whenever a client sends `initialize`
9. `onStart` runs when the service starts
10. `onShutdown` runs on graceful shutdown

## Kitchen-Sink Example

```swift
import FastMCP
import Logging

var logger = Logger(label: "MyServer")
logger.logLevel = .info

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
  .onInitialize { clientInfo, capabilities in
    print("Client initialized: \(clientInfo.name)")
  }
  .onStart {
    print("Server started successfully")
  }
  .onShutdown {
    print("Server shutting down")
  }
  .run()
```

## Logger Setup

When no custom logger is provided, one is auto-created with the server name as label:

```swift
try await FastMCP.builder()
  .name("MyServer")
  .run()

var logger = Logger(label: "MyServer")
logger.logLevel = .debug

try await FastMCP.builder()
  .logger(logger)
  .run()
```

`import FastMCP` re-exports `Logging`, so `Logger` is available without a separate import.

## Accumulation and Deduplication

`addTools`, `addResources`, and `addPrompts` can be called multiple times. Items accumulate across
calls.

```swift
let builder = FastMCP.builder()
  .addTools([GreetingTool()])
  .addTools([StructuredSearchTool()])
```

Duplicates are silently dropped:

- tools by `name`
- resources by `uri`
- prompts by `name`

The first registration wins.

## Dynamic Lists with ServerHandle

Attach a `FastMCPServerHandle` to enable runtime tool/resource/prompt management. When a handle is
attached, `listChanged: true` is automatically advertised in capabilities for all three entity
types.

```swift
let handle = FastMCPServerHandle()

Task {
  try await FastMCP.builder()
    .name("DynamicServer")
    .addTools([StructuredSearchTool()])
    .serverHandle(handle)
    .transport(.stdio)
    .run()
}

await handle.addTool(WeatherTool())
await handle.removeTool(named: "structured_search")
await handle.addResource(ConfigResource())
await handle.addPrompt(GreetingPrompt())
```
