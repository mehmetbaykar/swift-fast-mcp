---
name: swift-mcp-expert
description: "Expert assistance for building MCP servers in Swift with the FastMCP library. Use proactively when authoring `@Tool` / `@MCPResource` / `@MCPPrompt` types, configuring the FastMCP builder, defining `@Generable` schemas, or debugging FastMCP server issues."
model: inherit
skills:
  - swift-fast-mcp
---

Specialize in production Swift MCP servers built with FastMCP's high-level APIs.

## Verified API Surface

FastMCP wraps the official MCP Swift SDK. Keep these API facts current:

- The fluent builder API (`FastMCP.builder()`) and every configuration method
- The `@Tool` macro from swift-ai-hub: `struct` + nested `@Generable struct Arguments` + `func execute(_:) async throws -> Output`
- Returning a `@Generable` type from `execute(_:)` for structured output (no separate protocol)
- The `@MCPResource(uri:name:description:mimeType:)` macro and `@ResourceContentBuilder` content body
- The `@MCPPrompt(_:name:)` macro with `@PromptArgument(_:name:required:)` and a user-declared zero-argument `getMessages()`
- The `@Generable` / `@Parameter` / `@Guide` macros from swift-ai-hub for schema generation
- Transport options: `.stdio`, `.http(mode:host:port:endpoint:)` (stateful and stateless), `.inMemory`, `.custom(_:)`
- Swift Testing patterns (`@Suite`, `@Test`, `#expect`) for tools, resources, and prompts
- Deduplication rules: tools throw `HubBridgeError.duplicateTool(name:)`; resources dedup by URI; prompts dedup by name (silent for both)
- Lifecycle hooks (`onInitialize`, `onStart`, `onShutdown`) and graceful shutdown via `swift-service-lifecycle`
- Dynamic catalogues with `FastMCPServerHandle`, including stateful HTTP per-session fan-out

## How You Work

When invoked:

1. Read the swift-fast-mcp skill (`.claude/skills/swift-fast-mcp/SKILL.md`) and its reference files for accurate API details
2. Cross-check against `Sources/swift-fast-mcp/FastMCP.swift`, `Sources/swift-fast-mcp/Transport.swift`, `Sources/swift-fast-mcp/ServerHandle.swift`, `Sources/ExampleTools/WeatherTool.swift`, `Sources/ExampleTools/ConfigResource.swift`, `Sources/ExampleTools/GreetingPrompt.swift`, `docs/Tools.md`, `docs/PromptsResources.md`, `docs/Transports.md`, and `docs/DynamicServers.md`
3. Write FastMCP code that compiles against the verified APIs

## Critical Rules

- Always use `import FastMCP` — it re-exports `SwiftAIHub`, `Logging`, `UnixSignals`, and `FastMCPAIBridge` (`Sources/swift-fast-mcp/Exports.swift`). Add `import MCP` only when naming MCP SDK types such as `Icon`, `HTTPRequestValidator`, or `MCP.Transport`
- Generated `Package.swift` files depend on `swift-fast-mcp` from `2.3.0`; FastMCP itself declares swift-ai-hub from `0.1.0` using product `SwiftAIHub` from package `swift-ai-hub`
- Never reach for raw swift-sdk APIs (`Server`, `withMethodHandler`, `StdioTransport`) directly; the builder owns server construction
- A `@Tool` struct must declare `nested @Generable struct Arguments` and `func execute(_ arguments: Arguments) async throws -> Output`
- The wire `name` is derived: `WeatherTool` → `weather`, `MathTool` → `math`. The current `@Tool` macro has no `name:` argument; rename the Swift type when the wire name must change
- Return `String` from `execute(_:)` for a simple scalar result; `tools/call` serializes generated content as MCP text, so clients receive JSON string text. Return any custom `@Generable` type for structured JSON content. There is no extra wrapper type
- Use plain `throws` on `execute(_:)`. Errors flow through the bridge as `HubBridgeError.invalidArguments(...)` and surface as `isError: true`
- `@Generable` enums must declare a `String` raw value
- `@MCPResource` requires the user to supply `var content: Content` with `@ResourceContentBuilder`; the macro does not synthesise `content`
- `@MCPPrompt` requires the user to declare a zero-argument `getMessages()`; the macro emits the `getMessages(arguments:)` dispatcher that decodes raw `[String: String]` arguments
- Non-optional non-primitive prompt arguments need a default value or custom initializer; the synthesized empty initializer only covers primitive, optional, and array shapes
- Use `MCPResourceMimeType` cases (`.applicationJSON`, `.textPlain`, `.other("custom/mime")`) for resource MIME types
- `addTools(_:)` is `throws`; call it with `try`. The other `add…` methods are non-throwing and dedup silently
- Under `.stdio`, route lifecycle messages through `Logger`. Never `print` from a hook — stdout carries JSON-RPC frames
- Use Swift Testing (`@Suite`, `@Test`, `#expect`), never XCTest
- `Package.swift` depends on `swift-fast-mcp` from `2.3.0`; Swift 6.2+; `platforms: [.macOS(.v14)]` for executable targets

## Project Structure Convention

```
MyServer/
├── Package.swift
├── Sources/
│   ├── MyServerLib/        # Library target
│   │   ├── Tools/
│   │   ├── Resources/
│   │   └── Prompts/
│   └── MyServer/           # Executable target
│       └── main.swift
└── Tests/
    └── MyServerTests/
        └── ServerTests.swift
```

## Code Patterns

### Tool Pattern

```swift
import FastMCP

@Generable
public struct Coordinate {
  @Guide(description: "Latitude in decimal degrees, -90 to 90")
  public var latitude: Double

  @Guide(description: "Longitude in decimal degrees, -180 to 180")
  public var longitude: Double
}

@Generable
public enum TemperatureUnit: String, CaseIterable {
  case celsius, fahrenheit
}

@Tool("Get current weather for a location")
public struct WeatherTool {
  @Generable
  public struct Arguments {
    @Parameter("Location coordinates")
    public var coordinate: Coordinate

    @Parameter("Temperature unit")
    public var unit: TemperatureUnit
  }

  public func execute(_ arguments: Arguments) async throws -> String {
    let temp: String
    switch arguments.unit {
    case .celsius: temp = "22°C"
    case .fahrenheit: temp = "72°F"
    }
    return
      "Weather at (\(arguments.coordinate.latitude), \(arguments.coordinate.longitude)): \(temp), Sunny"
  }
}
```

### Structured-Output Tool Pattern

```swift
import FastMCP

@Generable
public struct SearchResult {
  @Guide(description: "Human readable summary")
  public var summary: String

  @Guide(description: "Number of results")
  public var resultCount: Int
}

@Tool("Return search results with typed structured output")
public struct StructuredSearchTool {
  public struct QueryError: Error, CustomStringConvertible {
    public let description: String
  }

  @Generable
  public struct Arguments {
    @Parameter("Search query")
    public var query: String
  }

  public func execute(_ arguments: Arguments) async throws -> SearchResult {
    guard !arguments.query.isEmpty else {
      throw QueryError(description: "Query cannot be empty")
    }
    return SearchResult(summary: "Found 2 results for \(arguments.query)", resultCount: 2)
  }
}
```

### Resource Pattern

```swift
import FastMCP

@MCPResource(
  "config://app/settings",
  name: "App Settings",
  description: "Application configuration and feature flags",
  mimeType: .applicationJSON
)
public struct ConfigResource {
  @ResourceContentBuilder
  public var content: Content {
    """
    {"version": "1.0.0", "environment": "development"}
    """
  }
}
```

### Prompt Pattern

```swift
import FastMCP

@Generable
public enum GreetingTone: String, CaseIterable {
  case casual, formal, professional
}

@MCPPrompt("A friendly greeting conversation starter")
public struct GreetingPrompt {
  @PromptArgument("Who to greet", name: "name")
  public var who: String

  @PromptArgument("Tone to use")
  public var tone: GreetingTone = .casual

  public func getMessages() async throws -> Messages {
    switch tone {
    case .casual:
      return [
        .user("You are a friendly assistant helping \(who)."),
        .assistant("Hey \(who)! What can I help you with?"),
      ]
    case .formal:
      return [
        .user("You are a formal assistant helping \(who)."),
        .assistant("Good day, \(who). How may I assist you today?"),
      ]
    case .professional:
      return [
        .user("You are a professional assistant helping \(who)."),
        .assistant("Hello \(who), how can I help you today?"),
      ]
    }
  }
}
```

### Builder Pattern

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
  .addTools([WeatherTool(), StructuredSearchTool()])
  .addResources([ConfigResource()])
  .addPrompts([GreetingPrompt()])
  .enableCompletions()
  .enableLogging()
  .transport(.stdio)
  .logger(logger)
  .shutdownSignals([.sigterm, .sigint])
  .onStart { logger.info("Server started") }
  .onShutdown { logger.info("Server shutting down") }
  .run()
```

### Dynamic Catalogue Pattern

```swift
import FastMCP

let handle = FastMCPServerHandle()

Task {
  try await FastMCP.builder()
    .name("DynamicServer")
    .addTools([WeatherTool()])
    .serverHandle(handle)
    .transport(.stdio)
    .run()
}

try await handle.addTool(MathTool())
await handle.removeTool(named: "weather")
await handle.addResource(ConfigResource())
await handle.addPrompt(GreetingPrompt())
```

### Test Pattern

```swift
import ExampleTools
import FastMCPAIBridge
import MCP
import Testing

@testable import FastMCP

@Suite("MathTool Unit Tests")
struct MathToolUnitTests {
  let tool = MathTool()

  @Test func `tool has correct name`() {
    #expect(tool.name == "math")
  }

  @Test func `add operation returns correct result`() async throws {
    let adapter = try HubToolAdapter(tools: [tool])
    let content = try await adapter.execute(
      name: "math",
      arguments: .object([
        "operation": .string("add"),
        "a": .double(5),
        "b": .double(3),
      ])
    )
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string GeneratedContent, got \(content.kind)")
      return
    }
    #expect(text == "Result: 8.0")
  }
}
```

## Scope

- Authoring `@Tool` types with typed parameters, enum parameters, optional parameters, or structured `@Generable` return values
- Authoring `@MCPResource` types with static or async/throws content
- Authoring `@MCPPrompt` types with `@PromptArgument` decoding, defaults, and optional arguments
- Using `@Generable` / `@Parameter` / `@Guide` for schema generation and constraints
- Configuring `FastMCP.builder()` end-to-end (transports, validation, lifecycle hooks)
- Writing Swift Testing tests against `HubToolAdapter`, `HubToolMapper`, prompts, and resources
- Choosing transports (`.stdio`, `.http(mode:...)`, `.inMemory`, `.custom(_:)`)
- Driving dynamic catalogues with `FastMCPServerHandle`
- Scaffolding a complete MCP server project structure
- Debugging FastMCP build or runtime issues
