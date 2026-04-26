---
name: swift-fast-mcp
description: 'Generate a complete MCP server project in Swift using the FastMCP library. Use when asked to create a Swift MCP server, build an MCP tool server, or scaffold a Model Context Protocol project in Swift.'
argument-hint: '[ServerName] [tools,resources,prompts]'
---

# FastMCP Server Generator

FastMCP is a Swift library for building Model Context Protocol servers on top of the official MCP Swift SDK. Tools are authored with the `@Tool` / `@Generable` / `@Parameter` / `@Guide` macros from swift-ai-hub and re-exported by FastMCP. Prompts and resources are authored with FastMCP's own `@MCPPrompt` / `@PromptArgument` and `@MCPResource` / `@ResourceContentBuilder` macros. The fluent `FastMCP.builder()` wires the catalogue and runs the server under a `ServiceGroup` for graceful shutdown.

## Argument Parsing

- `$ARGUMENTS[0]` = project name (e.g., `MyServer`). Default: `MCPServer`
- `$ARGUMENTS[1]` = comma-separated features: `tools`, `resources`, `prompts`. Default: all three.

## Project Structure

```
$ARGUMENTS[0]/
├── Package.swift
├── Sources/
│   ├── $ARGUMENTS[0]Lib/
│   │   ├── Tools/
│   │   │   └── ExampleTool.swift
│   │   ├── Resources/
│   │   │   └── ExampleResource.swift
│   │   └── Prompts/
│   │       └── ExamplePrompt.swift
│   └── $ARGUMENTS[0]/
│       └── main.swift
├── Tests/
│   └── $ARGUMENTS[0]Tests/
│       └── ServerTests.swift
└── README.md
```

Only include subdirectories for requested features (e.g., omit `Prompts/` if not in `$ARGUMENTS[1]`).

## Package.swift

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "$ARGUMENTS[0]",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/mehmetbaykar/swift-fast-mcp.git", from: "2.5.0"),
  ],
  targets: [
    .target(
      name: "$ARGUMENTS[0]Lib",
      dependencies: [
        .product(name: "FastMCP", package: "swift-fast-mcp"),
      ]
    ),
    .executableTarget(
      name: "$ARGUMENTS[0]",
      dependencies: ["$ARGUMENTS[0]Lib"]
    ),
    .testTarget(
      name: "$ARGUMENTS[0]Tests",
      dependencies: ["$ARGUMENTS[0]Lib"]
    ),
  ]
)
```

Notes:

- A single dependency on `swift-fast-mcp` is enough for a generated server. FastMCP transitively brings in the official MCP SDK, swift-ai-hub, swift-service-lifecycle, and swift-nio.
- The FastMCP package declares swift-ai-hub with `.package(url: "https://github.com/mehmetbaykar/swift-ai-hub", from: "0.1.0")` and depends on `.product(name: "SwiftAIHub", package: "swift-ai-hub")` in `Package.swift`.
- `import FastMCP` re-exports `FastMCPAIBridge`, `SwiftAIHub`, `Logging`, and `UnixSignals` (`Sources/swift-fast-mcp/Exports.swift`), so user files only need `import FastMCP`.
- Swift 6.2+, macOS 14+ to match swift-fast-mcp's own platform floor.

## main.swift

```swift
import FastMCP
import $ARGUMENTS[0]Lib

@main
struct $ARGUMENTS[0] {
  static func main() async throws {
    let logger: Logger = {
      var log = Logger(label: "$ARGUMENTS[0]")
      log.logLevel = .info
      return log
    }()

    try await FastMCP.builder()
      .name("$ARGUMENTS[0]")
      .version("1.0.0")
      .addTools([
        // Add tool instances here
      ])
      .addResources([
        // Add resource instances here
      ])
      .addPrompts([
        // Add prompt instances here
      ])
      .enableCompletions()
      .enableLogging()
      .transport(.stdio)
      .logger(logger)
      .shutdownSignals([.sigterm, .sigint])
      .onStart {
        logger.info("Server started")
      }
      .onShutdown {
        logger.info("Server shutting down")
      }
      .run()
  }
}
```

Under `.stdio`, stdout carries JSON-RPC frames — never `print` from a hook. Route lifecycle messages through the injected `Logger` (swift-log writes to stderr by default). Under `.http(...)`, either approach is safe.

`addTools(_:)` is `throws` and rejects duplicates eagerly (`Sources/swift-fast-mcp/FastMCP.swift:80`), so call it with `try`.

## Upstream MCP Aggregation

FastMCP can expose local SwiftAIHub tools and proxied tools from upstream MCP
servers through one downstream server. V1 supports upstream Streamable HTTP only:

```swift
try await FastMCP.builder()
  .name("$ARGUMENTS[0]")
  .addTools([
    // Local SwiftAIHub tools
  ])
  .addUpstreamMCPServers([
    .streamableHTTP(
      name: "firecrawl",
      endpoint: URL(string: "https://mcp.firecrawl.dev/v2/mcp")!,
      headers: ["Authorization": "Bearer <token>"]
    )
  ])
  .transport(.stdio)
  .logger(logger)
  .run()
```

Important constraints:

- Use `.streamableHTTP` for upstream aggregation. The SDK's
  `HTTPClientTransport` handles MCP Streamable HTTP.
- Do not document or generate stdio subprocess upstreams yet. FastMCP does not
  spawn `npx`, `uvx`, or `python` upstream servers in this version.
- The upstream server name is the default visible tool namespace:
  `name: "firecrawl"` exposes `firecrawl_scrape`. Pass `toolNamePrefix` to
  override the namespace, or `toolNamePrefix: ""` only when raw upstream names
  are intentional.
- Duplicate upstream server names are rejected eagerly. Duplicate visible tool
  names throw `HubBridgeError.duplicateTool`.
- Proxied tools preserve upstream `MCP.Tool` metadata and return the upstream
  `CallTool.Result`, including `structuredContent` when available.
- V1 aggregates tools only. Do not claim upstream resources/prompts,
  auto-reconnect/backoff, or upstream `notifications/tools/list_changed`
  passthrough support.
- Treat headers such as `Authorization` as secrets; recommend conservative
  production log levels when users pass sensitive upstream headers.

## Quick Reference: Tool

```swift
import FastMCP

@Generable
public enum TemperatureUnit: String, CaseIterable {
  case celsius, fahrenheit
}

@Tool("Get current weather for a location")
public struct WeatherTool {
  @Generable
  public struct Arguments {
    @Parameter("Location name or coordinates")
    public var location: String

    @Parameter("Temperature unit")
    public var unit: TemperatureUnit
  }

  public func execute(_ arguments: Arguments) async throws -> String {
    let temp = arguments.unit == .celsius ? "22°C" : "72°F"
    return "Weather in \(arguments.location): \(temp), Sunny"
  }
}
```

The `@Tool` macro derives the wire `name` by stripping a trailing `Tool` from the type name and lowercasing the first character (`WeatherTool` → `weather`). Description is the macro's string argument. The `Arguments` type must be a nested `@Generable struct Arguments`. Properties on the `Arguments` struct become schema fields; mark each with `@Parameter("…")` (or `@Guide(description:)`) for the description that reaches the wire.

There is no current `@Tool` `name:` parameter. Rename the Swift type when the wire name must change.

`execute(_:)` returns whatever you want the model to see. `String` flows through `GeneratedContent(kind: .string(...))`; `tools/call` serializes generated content as MCP text, so clients receive JSON string text for plain `String` returns. A custom `@Generable` return type flows out as a JSON-encoded text content block. See `docs/Tools.md` for the full wire shape and `../swift-ai-hub/docs/Macros.md` for the macro contract.

## Quick Reference: Structured Output

Return any `@Generable` type from `execute(_:)` to publish typed JSON content. Structured output is driven by the return type alone — no extra protocol or wrapper:

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

The bridge serialises the value through `GeneratedContent.jsonString` and emits a single `text` content block (`Sources/FastMCPAIBridge/HubToolAdapter.swift`). Errors thrown from `execute(_:)` are wrapped as `HubBridgeError.invalidArguments(...)` and surface as `isError: true` on the wire.

## Quick Reference: Resource

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

The macro emits the `uri`, `name`, `description`, `mimeType`, and a `public init()`, plus `extension … : MCPResource, Sendable`. The struct supplies `content` itself with `@ResourceContentBuilder`. `Content` is `[ResourceContentItem]`, and a string literal converts directly. Use `MCPResourceMimeType` cases such as `.applicationJSON`, `.textPlain`, `.textMarkdown`, or `.other("custom/mime")`.

## Quick Reference: Prompt

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

`@MCPPrompt(_:name:)` derives the wire `name` by stripping a trailing `Prompt` and lowercasing the first character (`GreetingPrompt` → `greeting`). Override with `name: "custom_name"`. Stored properties annotated with `@PromptArgument` become `PromptArgumentSpec` entries. The macro generates a dispatcher that decodes the raw `[String: String]` argument map and calls the user-declared `getMessages()`. Arguments are required unless the property is optional (`String?`) or has a default value.

For non-optional non-primitive prompt arguments, provide a default value or a custom initializer; the synthesized empty initializer only covers primitive, optional, and array shapes.

## Dynamic Lists with `FastMCPServerHandle`

Attach a `FastMCPServerHandle` to mutate the tool/resource/prompt catalogue after `run()` starts. Connected clients receive `notifications/{tools,resources,prompts}/list_changed` automatically.

```swift
import FastMCP

let handle = FastMCPServerHandle()

Task {
  try await FastMCP.builder()
    .name("DynamicServer")
    .addTools([WeatherTool()])
    .serverHandle(handle)
    .run()
}

// Later, from any task:
try await handle.addTool(MathTool())
await handle.removeTool(named: "weather")
await handle.addResource(ConfigResource())
await handle.removeResource(uri: "config://app/settings")
await handle.addPrompt(GreetingPrompt())
await handle.removePrompt(named: "greeting")
```

When a handle is attached, `listChanged: true` is advertised on every capability and all three (tools/resources/prompts) are advertised even when empty. Works with stdio, HTTP (stateful and stateless), in-memory, and custom transports. See `docs/DynamicServers.md` for the per-session HTTP flow.

## Deduplication Rules

- **Tools**: `addTools(_:)` and the handle's `addTool` / `addTools` both throw `HubBridgeError.duplicateTool(name:)` on a duplicate name. Failures fire before any partial mutation.
- **Resources**: deduplicated by `uri`. Duplicates are silently dropped, first registration wins.
- **Prompts**: deduplicated by `name`. Duplicates are silently dropped, first registration wins.

## Reference Files

- [reference/tools.md](reference/tools.md) — `@Tool` macro, `Arguments`, `execute(_:)`, structured returns, errors
- [reference/resources.md](reference/resources.md) — `@MCPResource`, `@ResourceContentBuilder`, `MCPResourceMimeType`
- [reference/prompts.md](reference/prompts.md) — `@MCPPrompt`, `@PromptArgument`, `PromptMessage` factories
- [reference/schemable.md](reference/schemable.md) — `@Generable` / `@Parameter` / `@Guide` reference
- [reference/builder-api.md](reference/builder-api.md) — every `FastMCP.Builder` method and its default
- [reference/transport.md](reference/transport.md) — pointer to `docs/Transports.md`
- [reference/testing.md](reference/testing.md) — Swift Testing patterns for tools, resources, prompts
- [reference/limitations.md](reference/limitations.md) — known constraints

Authoritative source files for cross-checking:

- `Sources/swift-fast-mcp/FastMCP.swift` — builder API
- `Sources/swift-fast-mcp/ServerHandle.swift` — dynamic catalogue API
- `Sources/swift-fast-mcp/MCPPrompt.swift` — prompt protocol and message types
- `Sources/swift-fast-mcp/MCPResource.swift` — resource protocol and content builder
- `Sources/swift-fast-mcp/Transport.swift` — `.stdio`, `.http`, `.inMemory`, `.custom`
- `Sources/swift-fast-mcp/MCPResourceMimeType.swift` — resource MIME enum
- `Sources/ExampleTools/WeatherTool.swift`
- `Sources/ExampleTools/MathTool.swift`
- `Sources/ExampleTools/GreetingTool.swift`
- `Sources/ExampleTools/ConfigResource.swift`
- `Sources/ExampleTools/GreetingPrompt.swift`
- `Sources/ExampleTools/StructuredSearchTool.swift`
- `docs/Tools.md`
- `docs/PromptsResources.md`
- `docs/Transports.md`
- `docs/DynamicServers.md`
- `../swift-ai-hub/docs/Macros.md` for the hub macros
- `../swift-ai-hub/Sources/SwiftAIHub/Tools/ToolMacros.swift`
- `../swift-ai-hub/Sources/SwiftAIHubMacros/ToolMacro.swift`

## Claude Desktop Integration

```json
{
  "mcpServers": {
    "$ARGUMENTS[0]": {
      "command": "/path/to/$ARGUMENTS[0]"
    }
  }
}
```

## Build and Run

```bash
swift build
swift run $ARGUMENTS[0]
swift test
swift build -c release
```
