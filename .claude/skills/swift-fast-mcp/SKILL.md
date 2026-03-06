---
name: swift-fast-mcp
description: 'Generate a complete MCP server project in Swift using the FastMCP library. Use when asked to create a Swift MCP server, build an MCP tool server, or scaffold a Model Context Protocol project in Swift.'
argument-hint: '[ServerName] [tools,resources,prompts]'
---

# FastMCP Server Generator

FastMCP is a high-level Swift library for building Model Context Protocol servers. It wraps the official MCP Swift SDK with a fluent builder API, protocol-based tools/resources/prompts, automatic JSON Schema generation via `@Schemable`, and lifecycle management.

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
    .package(url: "https://github.com/mehmetbaykar/swift-fast-mcp.git", from: "1.0.2"),
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

Key points:
- Single dependency on `swift-fast-mcp` — it transitively provides MCP, MCPToolkit, Logging, UnixSignals
- Swift 6.2+, macOS 14+
- Library target for tools/resources/prompts, executable target for entry point, test target

## main.swift

```swift
import FastMCP
import $ARGUMENTS[0]Lib
import Logging

@main
struct $ARGUMENTS[0] {
  static func main() async throws {
    var logger = Logger(label: "$ARGUMENTS[0]")
    logger.logLevel = .info

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
      .enableSampling()
      .transport(.stdio)
      .logger(logger)
      .shutdownSignals([.sigterm, .sigint])
      .onStart {
        print("Server started")
      }
      .onShutdown {
        print("Server shutting down")
      }
      .run()
  }
}
```

`import FastMCP` re-exports: MCP, MCPToolkit, Logging, UnixSignals. No other imports needed for tool/resource/prompt files.

## Deduplication Rules

- **Tools**: deduplicated by `name`. First registration wins.
- **Resources**: deduplicated by `uri`. First registration wins.
- **Prompts**: deduplicated by `name`. First registration wins.
- Duplicates are silently dropped (no warning logged).

## Quick Reference: Tool

```swift
import FastMCP

public struct GreetTool: MCPTool {
  public let name = "greet"
  public let description: String? = "Generate a greeting"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let name: String
    public init(name: String) { self.name = name }
  }

  public func call(with arguments: Parameters) async throws(ToolError) -> Content {
    [ToolContentItem(text: "Hello, \(arguments.name)!")]
  }
}
```

## Quick Reference: Resource

```swift
import FastMCP

public struct ConfigResource: MCPResource {
  public let uri = "config://app/settings"
  public let name = "App Settings"
  public let description: String? = "Application configuration"
  public let mimeType: String? = "application/json"

  public init() {}

  public var content: Content {
    """
    {"version": "1.0.0", "environment": "development"}
    """
  }
}
```

## Quick Reference: Prompt

```swift
import FastMCP

public struct GreetingPrompt: MCPPrompt {
  public let name = "greeting"
  public let description: String? = "A friendly greeting"

  public init() {}

  @Schemable
  public struct Arguments {
    public let name: String
    public init(name: String) { self.name = name }
  }

  public func getMessages(arguments: Arguments) async throws -> Messages {
    [
      .user("You are a friendly assistant helping \(arguments.name)."),
      .assistant("Hey \(arguments.name)! What can I help you with?"),
    ]
  }
}
```

## Reference Files

For detailed patterns and API reference, load files from the `reference/` directory:

- [reference/tools.md](reference/tools.md) — MCPTool protocol, ToolError, enum parameters, optional params
- [reference/resources.md](reference/resources.md) — MCPResource protocol, async content, MIME types
- [reference/prompts.md](reference/prompts.md) — MCPPrompt protocol, @PromptMessageBuilder, typed arguments
- [reference/schemable.md](reference/schemable.md) — @Schemable macro usage, enum schemas, optional params, nested types
- [reference/builder-api.md](reference/builder-api.md) — Complete FastMCP.builder() method reference, all options and defaults
- [reference/testing.md](reference/testing.md) — Swift Testing unit and integration tests
- [reference/transport.md](reference/transport.md) — Transport options: .stdio, .inMemory, .custom
- [reference/limitations.md](reference/limitations.md) — Known constraints and workarounds

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
