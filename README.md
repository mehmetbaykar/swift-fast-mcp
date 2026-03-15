# FastMCP

The fastest way to build MCP servers in Swift.

```swift
try await FastMCP.builder()
    .name("My Server")
    .addTools([WeatherTool()])
    .run()
```

Three lines to a working MCP server over stdio. Or serve over HTTP:

```swift
try await FastMCP.builder()
    .name("My Server")
    .addTools([WeatherTool()])
    .transport(.http(port: 8080))
    .run()
```

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mehmetbaykar/swift-fast-mcp", from: "2.0.0")
]
```

Then add `"FastMCP"` as a dependency of your target:

```swift
.target(
    name: "MyServer",
    dependencies: [
        .product(name: "FastMCP", package: "swift-fast-mcp")
    ]
)
```

FastMCP pulls in these dependencies automatically:

- [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) -- Official MCP Swift SDK
- [swift-mcp-toolkit](https://github.com/mehmetbaykar/swift-mcp-toolkit) -- Tool/Resource/Prompt protocol abstractions
- [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle) -- Graceful shutdown
- [swift-log](https://github.com/apple/swift-log) -- Logging
- [swift-nio](https://github.com/apple/swift-nio) -- HTTP transport (NIO is an internal dependency; not re-exported)

## Quick Start

### Stdio transport (default)

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
        [ToolContentItem(text: "Weather in \(args.location): 22C, Sunny")]
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

Connect it to Claude Desktop by adding to `claude_desktop_config.json`:

```json
{
    "mcpServers": {
        "weather": {
            "command": "/path/to/my-server"
        }
    }
}
```

### HTTP transport

```swift
@main
struct MyServer {
    static func main() async throws {
        try await FastMCP.builder()
            .name("Weather Server")
            .addTools([WeatherTool()])
            .transport(.http(port: 8080))
            .run()
        // Listening on http://127.0.0.1:8080/mcp
    }
}
```

## Transport Options

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

| Transport | Use Case |
|-----------|----------|
| `.stdio` | Claude Desktop, CLI tools. Default. |
| `.inMemory` | Unit testing. |
| `.http(...)` | Remote servers, multi-client access, web deployments. |
| `.custom(transport)` | Provide your own `MCP.Transport` implementation. |

### HTTPMode

```swift
public enum HTTPMode: Sendable {
    case stateful
    case stateless
}
```

**Stateful** (default) -- Full MCP Streamable HTTP. Each client gets a session with SSE streaming, resumability via `Last-Event-ID`, GET for server-initiated messages, and DELETE for session teardown.

**Stateless** -- Minimal HTTP. No sessions, direct JSON responses, POST only. Use when session management is handled externally or not needed.

```swift
// Stateful (default)
.transport(.http(port: 8080))
.transport(.http(mode: .stateful, host: "0.0.0.0", port: 3000, endpoint: "/mcp"))

// Stateless
.transport(.http(mode: .stateless, port: 8080))
```

## Builder API

All builder methods return a new `Builder` (value semantics) and can be chained.

### Server metadata

```swift
.name("My Server")               // Server name (default: process name)
.version("2.0.0")                // Server version (default: "1.0.0")
.title("My Display Name")        // Human-readable display name for UIs
.instructions("Use this server to...") // Instructions for LLM clients
.icons([...])                     // Server icons for display in UIs
```

### Capabilities

```swift
.addTools([WeatherTool(), MathTool()])   // Register tool implementations
.addResources([ConfigResource()])         // Register resource implementations
.addPrompts([GreetingPrompt()])          // Register prompt implementations
.enableCompletions()                      // Advertise completions capability
.enableLogging()                          // Advertise logging capability
```

Duplicate tools/resources/prompts (by name) are deduplicated automatically -- last one wins.

### Transport and infrastructure

```swift
.transport(.stdio)                       // Transport selection (default: .stdio)
.logger(myLogger)                        // Custom swift-log Logger
.shutdownSignals([.sigterm, .sigint])    // Unix signals for graceful shutdown (default: both)
```

### Lifecycle hooks

```swift
.onStart { print("Server started") }
.onShutdown { print("Server stopped") }
.onInitialize { clientInfo, capabilities in
    // Called when a client sends an initialize request.
    // Receives Client.Info and Client.Capabilities.
    // Useful for auth checks, logging, per-client setup.
    // Especially valuable for HTTP where multiple clients connect.
    print("Client: \(clientInfo.name) v\(clientInfo.version)")
}
```

### HTTP-specific configuration

```swift
.sessionTimeout(.seconds(1800))          // Idle session timeout (default: 3600s)
                                          // Only applies to .http with .stateful mode.

.httpValidation(
    allowedOrigins: ["https://example.com"],  // Allowed Origin headers (default: localhost only)
    customValidators: [MyAuthValidator()]     // Custom HTTPRequestValidator implementations
)
```

### Running

```swift
.run()  // Starts the server and blocks until shutdown
```

## HTTP Transport

### Multi-session model

In stateful HTTP mode, each connecting client gets its own independent `Server` + `Transport` pair. The server manages session lifecycle automatically.

### Session lifecycle (stateful mode)

1. Client sends POST to `/mcp` with an `initialize` JSON-RPC request (no session header).
2. Server creates a new `StatefulHTTPServerTransport` + `Server` pair, registers all tools/resources/prompts.
3. Transport generates a session ID, returned in the `Mcp-Session-Id` response header.
4. Subsequent requests include this header and are routed to the matching session.
5. Client sends DELETE to terminate the session.
6. A cleanup loop runs every 60 seconds, removing sessions idle longer than `sessionTimeout`.

### Stateless mode

1. Client sends POST to `/mcp` with a JSON-RPC request.
2. Server responds with direct JSON. No SSE, no session headers, no session tracking.

### Validation pipeline

The HTTP server validates incoming requests before processing. By default, only localhost origins are allowed.

To allow remote origins or add custom validation (e.g., bearer token auth), use `.httpValidation()`:

```swift
.httpValidation(
    allowedOrigins: ["https://myapp.com", "https://staging.myapp.com"],
    customValidators: [BearerTokenValidator(expectedToken: "...")]
)
```

Custom validators conform to `HTTPRequestValidator` from the MCP SDK.

### TLS

FastMCP does not handle TLS. Deploy behind a reverse proxy (nginx, Caddy) for HTTPS.

## Tools

AI-callable functions with automatic JSON Schema generation via `@Schemable`:

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

### Tool annotations

Add `annotations` to your `MCPTool` to provide hints about tool behavior:

```swift
struct WeatherTool: MCPTool {
    let name = "get_weather"
    let description: String? = "Get current weather"

    var annotations: Tool.Annotations {
        .init(readOnlyHint: true)
    }

    // ... Parameters and call as usual
}

struct MathTool: MCPTool {
    let name = "calculate"
    let description: String? = "Perform math"

    var annotations: Tool.Annotations {
        .init(readOnlyHint: true, idempotentHint: true)
    }

    // ...
}
```

Available annotation hints:

| Hint | Type | Default | Meaning |
|------|------|---------|---------|
| `readOnlyHint` | `Bool?` | `nil` | Tool does not modify state |
| `destructiveHint` | `Bool?` | `nil` | Tool may perform destructive operations |
| `idempotentHint` | `Bool?` | `nil` | Repeated calls with same args produce same result |
| `openWorldHint` | `Bool?` | `nil` | Tool interacts with external systems |

If you don't provide `annotations`, the default is `nil` (no annotations advertised).

## Resources

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

## Prompts

Reusable conversation templates with typed arguments via `@Schemable`:

```swift
struct GreetingPrompt: MCPPrompt {
    let name = "greeting"
    let description: String? = "A greeting template"

    @Schemable
    struct Arguments {
        let name: String
        let formal: Bool?
    }

    func getMessages(arguments: Arguments) async throws -> Messages {
        if arguments.formal == true {
            return [
                .user("You are a formal assistant helping \(arguments.name)."),
                .assistant("Good day, \(arguments.name). How may I assist you?"),
            ]
        } else {
            return [
                .user("You are a friendly assistant helping \(arguments.name)."),
                .assistant("Hey \(arguments.name)! What can I help you with?"),
            ]
        }
    }
}
```

## Full Example

A complete HTTP server with tools, resources, prompts, and lifecycle hooks:

```swift
import FastMCP
import Logging

@main
struct ExampleServer {
    static func main() async throws {
        var logger = Logger(label: "my-server")
        logger.logLevel = .info

        try await FastMCP.builder()
            .name("Example Server")
            .title("Example MCP Server")
            .version("2.0.0")
            .instructions("This server provides weather and math tools.")

            .addTools([WeatherTool(), MathTool()])
            .addResources([ConfigResource()])
            .addPrompts([GreetingPrompt()])

            .enableCompletions()
            .enableLogging()

            .transport(.http(port: 8080))

            .logger(logger)
            .shutdownSignals([.sigterm, .sigint])

            .sessionTimeout(.seconds(1800))
            .httpValidation(allowedOrigins: ["https://myapp.com"])

            .onInitialize { clientInfo, capabilities in
                print("Client connected: \(clientInfo.name) v\(clientInfo.version)")
            }
            .onStart {
                print("Server started on http://127.0.0.1:8080/mcp")
            }
            .onShutdown {
                print("Server shutting down")
            }

            .run()
    }
}
```

## Platform Support

- macOS 14+
- Linux (via `#if canImport(FoundationNetworking)` guards)
- Swift 6.2+

## Claude Code Integration

FastMCP ships with a [Claude Code skill](https://docs.anthropic.com/en/docs/claude-code/skills) and a [subagent](https://docs.anthropic.com/en/docs/claude-code/sub-agents) that let Claude Code scaffold and build MCP server projects for you.

### Setup

Copy the `skills/` and `.claude/` directories into your project:

```bash
# Copy the skill (project scaffolding)
cp -r skills/ .claude/skills/

# Copy the agent (expert assistance)
cp -r .claude/agents/ .claude/agents/
```

### Usage

**Scaffold a new project** with the skill:

```
/swift-fast-mcp MyServer tools,resources,prompts
```

Claude generates a complete project with Package.swift, typed tools/resources/prompts, tests, and Claude Desktop configuration.

**Get expert help** with the subagent:

Claude automatically delegates to the `swift-mcp-expert` agent when you ask about MCPTool, MCPResource, MCPPrompt implementations, the builder API, `@Schemable` types, or testing patterns. You can also invoke it explicitly:

```
Use the swift-mcp-expert to help me build a weather tool
```

## License

MIT
