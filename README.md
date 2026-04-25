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
    .package(url: "https://github.com/mehmetbaykar/swift-fast-mcp", from: "2.3.0")
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
- [swift-ai-hub](https://github.com/mehmetbaykar/swift-ai-hub) -- `@Tool` / `@Generable` / `@Parameter` / `@Guide` macros and the `Tool` protocol surface
- [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle) -- Graceful shutdown
- [swift-syntax](https://github.com/swiftlang/swift-syntax) -- Compiler plugin for `@MCPPrompt` / `@MCPResource`
- [swift-nio](https://github.com/apple/swift-nio) -- HTTP transport (NIO is an internal dependency; not re-exported)

## Quick Start

### Stdio transport (default)

```swift
import FastMCP

@Tool("Get weather for a location")
struct WeatherTool {
    @Generable
    struct Arguments {
        @Parameter("City or coordinates")
        var location: String
    }

    func execute(_ arguments: Arguments) async throws -> String {
        "Weather in \(arguments.location): 22°C, Sunny"
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
.version("2.2.0")                // Server version (default: "1.0.0")
.title("My Display Name")        // Human-readable display name for UIs
.instructions("Use this server to...") // Instructions for LLM clients
.icons([...])                     // Server icons for display in UIs
```

### Capabilities

```swift
.addTools([WeatherTool(), MathTool(), StructuredSearchTool()])   // Register tool implementations
.addResources([ConfigResource()])         // Register resource implementations
.addPrompts([GreetingPrompt()])          // Register prompt implementations
.enableCompletions()                      // Advertise completions capability
.enableLogging()                          // Advertise logging capability
```

Duplicate tools/resources/prompts are deduplicated automatically. The first registration wins.

### Transport and infrastructure

```swift
.transport(.stdio)                       // Transport selection (default: .stdio)
.logger(myLogger)                        // Custom swift-log Logger
.shutdownSignals([.sigterm, .sigint])    // Unix signals for graceful shutdown (default: both)
```

### Lifecycle hooks

Under `.stdio` (the default), stdout carries JSON-RPC frames — do not use `print` in hooks. Route messages through the injected `Logger` instead (swift-log's default handler writes to stderr). Under `.http`, either approach is safe.

```swift
.onStart { logger.info("Server started") }
.onShutdown { logger.info("Server stopped") }
.onInitialize { clientInfo, capabilities in
    // Called when a client sends an initialize request.
    // Receives Client.Info and Client.Capabilities.
    // Useful for auth checks, logging, per-client setup.
    // Especially valuable for HTTP where multiple clients connect.
    logger.info("Client: \(clientInfo.name) v\(clientInfo.version)")
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

AI-callable functions with JSON Schema generated by the `@Generable` macro on a nested
`Arguments` struct. The tool's name is derived from the struct name (`MathTool` → `math`)
and its return type from the body of `execute(_:)`:

```swift
@Generable
enum Operation: String, CaseIterable {
    case add, subtract, multiply, divide
}

@Tool("Perform math operations")
struct MathTool {
    @Generable
    struct Arguments {
        @Parameter("Operation") var operation: Operation
        @Parameter("First operand") var a: Double
        @Parameter("Second operand") var b: Double
    }

    func execute(_ arguments: Arguments) async throws -> String {
        let result = switch arguments.operation {
        case .add: arguments.a + arguments.b
        case .subtract: arguments.a - arguments.b
        case .multiply: arguments.a * arguments.b
        case .divide: arguments.a / arguments.b
        }
        return "Result: \(result)"
    }
}
```

## Resources

Expose data to AI models:

```swift
@MCPResource(
    "config://app/settings",
    name: "App Settings",
    description: "Application configuration",
    mimeType: .applicationJSON
)
struct ConfigResource {
    @ResourceContentBuilder
    var content: Content {
        """
        {"theme": "dark", "version": "1.0.0"}
        """
    }
}
```

## Prompts

Reusable conversation templates with typed arguments via `@PromptArgument`:

```swift
@MCPPrompt("A greeting template")
struct GreetingPrompt {
    @PromptArgument("Who to greet")
    var name: String

    @PromptArgument("Use formal tone")
    var formal: Bool = false

    func getMessages() async throws -> Messages {
        if formal {
            return [
                .user("You are a formal assistant helping \(name)."),
                .assistant("Good day, \(name). How may I assist you?"),
            ]
        } else {
            return [
                .user("You are a friendly assistant helping \(name)."),
                .assistant("Hey \(name)! What can I help you with?"),
            ]
        }
    }
}
```

## Full Example

A complete stdio server with tools, resources, prompts, and lifecycle hooks — the canonical MCP setup for Claude Desktop and CLI clients that spawn the server as a subprocess. This matches the stdio transport/lifecycle pattern used in the shipped `Sources/Example/ExampleServer.swift` (which wires up its own tools and metadata). For an HTTP-specific variant (with `.httpValidation`, `.sessionTimeout`, etc.), see the [HTTP transport](#http-transport) section above.

```swift
import FastMCP
import Logging

@main
struct ExampleServer {
    static func main() async throws {
        let logger: Logger = {
            var log = Logger(label: "my-server")
            log.logLevel = .info
            return log
        }()

        try await FastMCP.builder()
            .name("Example Server")
            .title("Example MCP Server")
            .version("2.2.0")
            .instructions("This server provides weather, math, and structured search tools.")

            .addTools([WeatherTool(), MathTool(), StructuredSearchTool()])
            .addResources([ConfigResource()])
            .addPrompts([GreetingPrompt()])

            .enableCompletions()
            .enableLogging()

            .transport(.stdio)

            .logger(logger)
            .shutdownSignals([.sigterm, .sigint])

            // Stdio owns stdout for JSON-RPC framing — route lifecycle messages
            // through `logger` (stderr) so `print` never corrupts the wire.
            .onInitialize { clientInfo, _ in
                logger.info("Client connected: \(clientInfo.name) v\(clientInfo.version)")
            }
            .onStart {
                logger.info("Server started on stdio")
            }
            .onShutdown {
                logger.info("Server shutting down")
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

Claude automatically delegates to the `swift-mcp-expert` agent when you ask about `@Tool`, `@MCPResource`, `@MCPPrompt` implementations, the builder API, `@Generable` types, or testing patterns. You can also invoke it explicitly:

```
Use the swift-mcp-expert to help me build a weather tool
```

## Documentation

- [docs/Tools.md](docs/Tools.md) — exposing `@Tool` structs from swift-ai-hub through an MCP server
- [docs/PromptsResources.md](docs/PromptsResources.md) — `@MCPPrompt`, `@MCPResource`, `@PromptArgument`, `MCPResourceMimeType`
- [docs/Transports.md](docs/Transports.md) — stdio, HTTP (stateful / stateless), in-memory, custom; `httpValidation`; ServiceGroup lifecycle
- [docs/DynamicServers.md](docs/DynamicServers.md) — `FastMCPServerHandle` for adding / removing tools, resources, and prompts after `run()` starts

The `@Tool`, `@Generable`, `@Parameter`, and `@Guide` macros come from
[swift-ai-hub](https://github.com/mehmetbaykar/swift-ai-hub) — see its
[docs/Macros.md](https://github.com/mehmetbaykar/swift-ai-hub/blob/main/docs/Macros.md)
for the macro reference.

## License

MIT
