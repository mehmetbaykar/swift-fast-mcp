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
| `icons()` | `func icons(_ icons: [String]) -> Builder` | `nil` |
| `addTools()` | `func addTools(_ newTools: [any MCPTool]) -> Builder` | `[]` |
| `addResources()` | `func addResources(_ newResources: [any MCPResource]) -> Builder` | `[]` |
| `addPrompts()` | `func addPrompts(_ newPrompts: [any MCPPrompt]) -> Builder` | `[]` |
| `enableCompletions()` | `func enableCompletions(_ enabled: Bool = true) -> Builder` | `false` |
| `enableLogging()` | `func enableLogging(_ enabled: Bool = true) -> Builder` | `false` |
| `transport()` | `func transport(_ transport: Transport) -> Builder` | `.stdio` |
| `logger()` | `func logger(_ logger: Logger) -> Builder` | `nil` (auto-created from server name) |
| `shutdownSignals()` | `func shutdownSignals(_ signals: [UnixSignal]) -> Builder` | `[.sigterm, .sigint]` |
| `onStart()` | `func onStart(_ handler: @escaping @Sendable () async -> Void) -> Builder` | `nil` |
| `onShutdown()` | `func onShutdown(_ handler: @escaping @Sendable () async -> Void) -> Builder` | `nil` |
| `onInitialize()` | `func onInitialize(_ handler: @escaping @Sendable () async -> Void) -> Builder` | `nil` |
| `sessionTimeout()` | `func sessionTimeout(_ timeout: Duration) -> Builder` | `nil` |
| `httpValidation()` | `func httpValidation(_ handler: @escaping @Sendable (HTTPRequest) -> Bool) -> Builder` | `nil` |
| `run()` | `func run() async throws` | -- |

## Value Semantics

Each method returns a new `Builder` copy. The original is not modified:

```swift
let base = FastMCP.builder().name("Base")
let modified = base.name("Modified")
// base.serverName == "Base"
// modified.serverName == "Modified"
```

## Execution Order

When `run()` is called:

1. Logger is created (custom or auto from server name)
2. Warning logged if no tools, resources, or prompts registered
3. Server capabilities built from registered components
4. MCP `Server` created with name, version, capabilities
5. Tools, resources, prompts registered on the server
6. `onInitialize` handler called (if set)
7. Transport created (stdio, http, inMemory, or custom)
8. `FastMCPService` wraps server + transport
9. For HTTP: binds to host/port, starts listening
10. `ServiceGroup` manages lifecycle with shutdown signals
11. `onStart` handler called
12. Server starts and waits for completion
13. `onShutdown` handler called on graceful shutdown

## Kitchen-Sink Example

Stdio example:

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
    MathTool(),
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
  .transport(.stdio)
  .logger(logger)
  .shutdownSignals([.sigterm, .sigint])
  .onInitialize {
    print("Server initialized")
  }
  .onStart {
    print("Server started successfully")
  }
  .onShutdown {
    print("Server shutting down")
  }
  .run()
```

HTTP example:

```swift
try await FastMCP.builder()
  .name("MyHTTPServer")
  .version("1.0.0")
  .addTools([WeatherTool()])
  .enableCompletions()
  .enableLogging()
  .transport(.http(mode: .stateful, host: "127.0.0.1", port: 8080))
  .sessionTimeout(.seconds(300))
  .httpValidation { request in
    request.headerFields.contains(.authorization)
  }
  .onStart {
    print("HTTP server listening on port 8080")
  }
  .run()
```

## Logger Setup

When no custom logger is provided, one is auto-created with the server name as label:

```swift
// Auto logger (label = server name)
try await FastMCP.builder()
  .name("MyServer")
  .run()

// Custom logger with specific level
var logger = Logger(label: "MyServer")
logger.logLevel = .debug
try await FastMCP.builder()
  .logger(logger)
  .run()
```

`import FastMCP` re-exports `Logging`, so `Logger` is available without a separate import.

## Accumulation

`addTools`, `addResources`, and `addPrompts` can be called multiple times. Items accumulate across calls:

```swift
let builder = FastMCP.builder()
  .addTools([GreetingTool()])     // 1 tool
  .addTools([MathTool()])         // 2 tools total
```

## FastMCPError

Error type thrown by FastMCP operations:

```swift
public enum FastMCPError: Error, LocalizedError, Sendable {
  case portInUse(Int)
  case invalidConfiguration(String)
  case authRequiredForHTTP
  case serverStartFailed(String)
  case generic(Error)
}
```
