# FastMCP

The fastest way to build MCP servers in Swift.

```swift
try await FastMCP.builder()
    .name("My Server")
    .addTools([WeatherTool()])
    .run()
```

That's it. Three lines to a working MCP server.

## Why FastMCP?

- **Zero boilerplate** - No manual JSON-RPC handling, no protocol implementation
- **Type-safe** - Swift-native with full `Sendable` support
- **Declarative** - Fluent builder API that reads like configuration
- **Complete** - Tools, Resources, Prompts, and Sampling out of the box
- **Production-ready** - Graceful shutdown, logging, lifecycle hooks included

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/mehmetbaykar/swift-fast-mcp", from: "1.0.0")
]
```

## 30-Second Example

```swift
import FastMCP

struct WeatherTool: MCPTool {
    let name = "get_weather"
    let description: String? = "Get weather for a location"

    @Schemable
    struct Parameters: Sendable {
        let location: String
    }

    func call(with args: Parameters) async throws(ToolError) -> Content {
        [ToolContentItem(text: "Weather in \(args.location): 22°C, Sunny")]
    }
}

@main
struct MyServer {
    static func main() async throws {
        try await FastMCP.builder()
            .name("Weather Server")
            .addTools([WeatherTool()])
            .run()
    }
}
```

Build it. Run it. Connect it to Claude Desktop. Done.

## Full Feature Set

### Tools
AI-callable functions with automatic schema generation:

```swift
struct MathTool: MCPTool {
    let name = "calculate"
    let description: String? = "Perform math operations"

    @Schemable
    struct Parameters: Sendable {
        let operation: Operation
        let a: Double
        let b: Double
    }

    @Schemable
    enum Operation: String, Sendable {
        case add, subtract, multiply, divide
    }

    func call(with args: Parameters) async throws(ToolError) -> Content {
        let result = switch args.operation {
            case .add: args.a + args.b
            case .subtract: args.a - args.b
            case .multiply: args.a * args.b
            case .divide: args.a / args.b
        }
        return [ToolContentItem(text: "Result: \(result)")]
    }
}
```

### Resources
Expose data to AI models:

```swift
struct ConfigResource: MCPResource {
    let uri = "config://app/settings"
    let name = "App Settings"
    let description: String? = "Application configuration"
    let mimeType: String? = "application/json"

    var content: Content {
        """
        {"theme": "dark", "version": "1.0.0"}
        """
    }
}
```

### Prompts
Reusable conversation templates:

```swift
struct GreetingPrompt: MCPPrompt {
    let name = "greeting"
    let description: String? = "A greeting template"
    let arguments: [Prompt.Argument]? = [
        .init(name: "name", description: "Person's name", required: true)
    ]

    func getMessages(arguments: [String: Value]?) async throws -> [Prompt.Message] {
        let name = arguments?["name"]?.stringValue ?? "friend"
        return [
            .user("You are helping \(name)."),
            .assistant("Hello \(name)! How can I help?")
        ]
    }
}
```

## Builder API

```swift
try await FastMCP.builder()
    .name("My Server")
    .version("1.0.0")
    .addTools([WeatherTool(), MathTool()])
    .addResources([ConfigResource()])
    .addPrompts([GreetingPrompt()])
    .enableSampling()
    .transport(.stdio)
    .logLevel(.info)
    .shutdownSignals([.sigterm, .sigint])
    .onStart { print("Started") }
    .onShutdown { print("Stopped") }
    .run()
```

## Transport Options

| Transport | Use Case |
|-----------|----------|
| `.stdio` | Claude Desktop, CLI tools |
| `.inMemory` | Unit testing |
| `.custom(transport)` | Your own implementation |

## Claude Desktop

Add to `claude_desktop_config.json`:

```json
{
    "mcpServers": {
        "my-server": {
            "command": "/path/to/my-server"
        }
    }
}
```

## Requirements

- macOS 14+
- Swift 6.0+

## Dependencies

- [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) - Official MCP Swift SDK
- [swift-mcp-toolkit](https://github.com/mehmetbaykar/swift-mcp-toolkit) - Tool/Resource abstractions
- [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle) - Graceful shutdown
- [swift-log](https://github.com/apple/swift-log) - Logging

## License

MIT
