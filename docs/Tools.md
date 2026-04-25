# Tools — wiring hub tools onto the MCP wire

This document covers the bridge: how a `SwiftAIHub.Tool` value becomes an MCP `tools/list` entry and a callable `tools/call` endpoint, and what the wire actually sees on the way out.

## One declaration, two call sites

A `SwiftAIHub.Tool` is `Sendable` (`swift-ai-hub/Sources/SwiftAIHub/Tools/Tool.swift:42`). The same instance can be handed to a `FastMCP.Builder` and to a `LanguageModelSession(tools:)` (`swift-ai-hub/Sources/SwiftAIHub/Core/LanguageModelSession.swift:75`). Neither call site mutates the tool — they read `name`, `description`, `parameters`, and dispatch through `call(arguments:)`. Whether a tool is external (MCP), internal (LLM loop), or both is a wiring decision made at the registration site, not a property of the struct.

```swift
let weather = WeatherTool()

// Exposed over MCP — any connected client can list/call it.
try await FastMCP.builder()
  .name("hybrid-server")
  .version("1.0.0")
  .addTools([weather])
  .transport(.stdio)
  .run()

// Exposed to an LLM only — the model can invoke it mid-respond.
let session = LanguageModelSession(model: provider, tools: [weather])
```

The full dual-use story (including a tool that the server runs internally but does not expose to MCP clients) is in [`swift-ai-hub/docs/05-tools-dual-use.md`](../../swift-ai-hub/docs/05-tools-dual-use.md).

## What `addTools` actually does

`Builder.addTools(_:)` is the entry point that exposes hub tools over MCP. It is `throws` and rejects duplicates eagerly — see `Sources/swift-fast-mcp/FastMCP.swift:80`:

```swift
public func addTools(_ newTools: [any SwiftAIHub.Tool]) throws -> Builder
```

When `Builder.run()` fires, it constructs a `HubToolAdapter` from the collected tools (`Sources/swift-fast-mcp/FastMCP.swift:203`), then calls `server.register(hubTools:)` which installs both `tools/list` and `tools/call` method handlers (`Sources/FastMCPAIBridge/HubServerRegistrar.swift:13`). From that moment the MCP server speaks the wire on the tools' behalf. The four pieces:

| Concern | File | Symbol |
|---|---|---|
| Schema projection (hub `GenerationSchema` → JSON Schema `Value`) | `Sources/FastMCPAIBridge/HubToolMapper.swift:25` | `HubToolMapper.inputSchema(for:)` |
| Argument decoding (MCP `Value` → hub `GeneratedContent`) | `Sources/FastMCPAIBridge/HubValueMapper.swift:10` | `HubValueMapper.generatedContent(from:)` |
| Execution dispatch (decode → `call(arguments:)` → segments) | `Sources/FastMCPAIBridge/HubToolAdapter.swift:73` | `HubToolAdapter.makeContent(name:arguments:)` |
| Error translation (Swift `Error` → `CallTool.Result(isError: true)`) | `Sources/FastMCPAIBridge/HubErrorMapper.swift:11` | `HubErrorMapper.mapCallToolError(_:toolName:)` |

The dispatch path inside `makeContent` is: look the tool up by name, run `HubValueMapper.generatedContent(from:)` on the MCP arguments, hand them to the tool's `makeOutputSegments(from:)` (the protocol-level entry point that decodes arguments, invokes `call`, and produces transcript segments), and map each segment to an MCP `Tool.Content` block. Argument decoding failures and tool execution failures are wrapped as `HubBridgeError.invalidArguments(tool:reason:)` before they reach `HubErrorMapper` (`Sources/FastMCPAIBridge/HubToolAdapter.swift:83`).

The adapter is an `actor`, so dynamic `register` / `unregister` is safe alongside concurrent in-flight `tools/call` dispatches.

## What the wire sees for `tools/list`

For the canonical example, `WeatherTool` is declared in `Sources/ExampleTools/WeatherTool.swift:17` and its `execute(_:)` implementation is at `Sources/ExampleTools/WeatherTool.swift:28`. The published tool name is the hub tool's `name`; the example server registers `WeatherTool`, `MathTool`, `GreetingTool`, and `StructuredSearchTool` at `Sources/Example/ExampleServer.swift:21`.

`HubToolMapper.mapTool(_:)` produces an `MCP.Tool` with `name`, `description`, and an `inputSchema` projected from the hub tool's `parameters` (`Sources/FastMCPAIBridge/HubToolMapper.swift:9`). The mapper round-trips the schema through JSON, then walks the result inlining any `{"$ref": "#/$defs/X"}` references with cycle guards (`Sources/FastMCPAIBridge/HubToolMapper.swift:60`) — most MCP clients do not resolve JSON Schema `$ref`, so the wire schema is fully dereferenced before it leaves the server.

A client calling `tools/list` against a server registered with `[WeatherTool()]` sees:

```json
{
  "tools": [
    {
      "name": "weather",
      "description": "Get current weather for a location",
      "inputSchema": {
        "additionalProperties": false,
        "description": "Generated Arguments",
        "type": "object",
        "properties": {
          "coordinate": {
            "additionalProperties": false,
            "description": "Generated Coordinate",
            "type": "object",
            "properties": {
              "latitude": {
                "type": "number",
                "description": "Latitude in decimal degrees, -90 to 90"
              },
              "longitude": {
                "type": "number",
                "description": "Longitude in decimal degrees, -180 to 180"
              }
            },
            "required": ["latitude", "longitude"]
          },
          "unit": {
            "type": "string",
            "enum": ["celsius", "fahrenheit"],
            "description": "Generated TemperatureUnit"
          }
        },
        "required": ["coordinate", "unit"]
      }
    }
  ]
}
```

Key ordering, including `required` array ordering, is not stable. The shape — top-level `type: "object"`, `additionalProperties: false`, inlined nested `Coordinate`, enum-as-`string`-with-`enum` — comes from `GenerationSchema` encoding and `HubToolMapper` dereferencing.

## What the wire sees for `tools/call`

A client calling:

```json
{
  "method": "tools/call",
  "params": {
    "name": "weather",
    "arguments": {
      "coordinate": {"latitude": 37.77, "longitude": -122.42},
      "unit": "celsius"
    }
  }
}
```

routes through `HubServerRegistrar`'s `CallTool` handler. `params.arguments` is wrapped into `Value.object(...)`, handed to `HubToolAdapter.makeContent(name:arguments:)`, decoded to `GeneratedContent`, decoded again into `WeatherTool.Arguments` (this is where invalid types fail — see Errors below), then `execute(_:)` runs.

For this `String`-returning example, the wire response is a single `text` content block whose payload is JSON string text:

```json
{
  "content": [
    {"type": "text", "text": "\"Weather at (37.77, -122.42): 22°C, Sunny\""}
  ],
  "isError": false
}
```

## Returning content

The shape of a tool's `execute` return type drives the wire shape. The protocol-default `makeOutputSegments(from:)` handles three cases (`swift-ai-hub/Sources/SwiftAIHub/Tools/Tool.swift:122`):

- **`ConvertibleToGeneratedContent` output** → one `Transcript.Segment.structure` carrying `GeneratedContent` (`swift-ai-hub/Sources/SwiftAIHub/Tools/Tool.swift:128`). The bridge method returns `[MCP.Tool.Content]`; `Tool.Content` has no structured-content case, and `HubServerRegistrar` builds `CallTool.Result(content:isError:)` without `structuredContent` (`Sources/FastMCPAIBridge/HubServerRegistrar.swift:23`). `HubToolAdapter` serializes the structure to JSON text via `GeneratedContent.jsonString` and emits a `.text` block (`Sources/FastMCPAIBridge/HubToolAdapter.swift:147`). `String` follows this path because it conforms to `Generable` (`swift-ai-hub/Sources/SwiftAIHub/Generation/Generable.swift:137`).
- **Direct `String` output that did not match the previous branch** → one `Transcript.Segment.text` (`swift-ai-hub/Sources/SwiftAIHub/Tools/Tool.swift:134`). The adapter maps it to a single MCP `.text` content block.
- **Anything else `PromptRepresentable`** → `output.promptRepresentation.description`, wrapped as a single `.text` segment (`swift-ai-hub/Sources/SwiftAIHub/Tools/Tool.swift:138`).

Tools that need to emit images can override `makeOutputSegments(from:)` directly and return `Transcript.Segment.image(...)`. The adapter preserves typed image data: `.image(.data(bytes, mimeType))` becomes an MCP `.image(data: base64, mimeType:)` block, and `.image(.url(url))` becomes a `.resourceLink(uri:)` wire block with type `resource_link` (the MCP image content type requires inline data + mime, so URL-only images surface as a resource link rather than dropping the URL on the floor) — see `Sources/FastMCPAIBridge/HubToolAdapter.swift:131`.

For the `StructuredSearchTool` example, calling with `{"query": "swift"}` yields:

```json
{
  "content": [
    {"type": "text", "text": "{\"resultCount\":2,\"summary\":\"Found 2 results for swift\"}"}
  ],
  "isError": false
}
```

Note: there is a sibling `HubToolAdapter.execute(name:arguments:)` entry point that returns `GeneratedContent` instead of `[MCP.Tool.Content]`. `HubServerRegistrar` does **not** use it for `tools/call` — the registrar uses `makeContent` so that image segments stay typed. `execute` is kept for callers who want a hub-shaped result; it preserves structured segments as `GeneratedContent`, turns image URLs into URL strings, and collapses image data to `"[image]"` (`Sources/FastMCPAIBridge/HubToolAdapter.swift:112`).

## Errors

When argument decoding or tool execution throws, `HubToolAdapter.makeContent` catches the failure and rethrows `HubBridgeError.invalidArguments(tool:, reason:)` (`Sources/FastMCPAIBridge/HubToolAdapter.swift:83`). The sibling `execute(name:arguments:)` path wraps the same failures in its private dispatch path (`Sources/FastMCPAIBridge/HubToolAdapter.swift:97`). The `CallTool` handler catches bridge errors and routes through `HubErrorMapper.mapCallToolError`, which produces a wire-level error result rather than throwing through the handler:

```swift
public static func mapCallToolError(_ error: Error, toolName: String) -> CallTool.Result {
  let message: String
  switch error {
  case let bridgeError as HubBridgeError:
    message = bridgeError.description
  default:
    message = "\(error)"
  }
  return CallTool.Result(
    content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
}
```

Three observable behaviors:

- `HubBridgeError.toolNotFound(name)` — caller invoked an unregistered tool. Wire message: `"Unknown tool: <name>"`.
- `HubBridgeError.invalidArguments(tool:, reason:)` — argument decoding failed, or the tool itself threw. Wire message: `"Invalid arguments for <tool>: <reason>"`. This is also the channel by which a domain error from inside `execute` (for example, `MathTool.CalculationError(description: "Division by zero")` at `Sources/ExampleTools/MathTool.swift:33`) reaches the client; it is wrapped under the same case rather than passed through verbatim.
- Anything else — string-interpolated via `"\(error)"`.

Either way, the response is `isError: true` with a single `.text` content block. The MCP connection stays up.

## Multiple tools and name collisions

`Builder.addTools` deduplicates eagerly. Passing the same tool name twice — across one call or across several — throws `HubBridgeError.duplicateTool(name:)` synchronously. From `Sources/swift-fast-mcp/FastMCP.swift:80`:

```swift
public func addTools(_ newTools: [any SwiftAIHub.Tool]) throws -> Builder {
  var copy = self
  var existingNames = Set(copy.hubTools.map { $0.name })
  for tool in newTools {
    if existingNames.contains(tool.name) {
      throw HubBridgeError.duplicateTool(name: tool.name)
    }
    existingNames.insert(tool.name)
    copy.hubTools.append(tool)
  }
  return copy
}
```

The same check fires inside `HubToolAdapter` itself, both on seeded init and on `register(_:)` (`Sources/FastMCPAIBridge/HubToolAdapter.swift:15`, `Sources/FastMCPAIBridge/HubToolAdapter.swift:24`):

```swift
public init(tools: [any SwiftAIHub.Tool]) throws {
  for tool in tools {
    if self.tools[tool.name] != nil {
      throw HubBridgeError.duplicateTool(name: tool.name)
    }
    self.tools[tool.name] = tool
  }
}

public func register(_ tool: any SwiftAIHub.Tool) throws {
  if tools[tool.name] != nil {
    throw HubBridgeError.duplicateTool(name: tool.name)
  }
  tools[tool.name] = tool
}
```

So a duplicate wire name is always a registration-time failure, never a silent overwrite. Two tools with the same `name` collide; ensure unique names before registration.

A typical multi-tool registration:

```swift
try await FastMCP.builder()
  .name("example-server")
  .version("1.0.0")
  .addTools([
    WeatherTool(),
    MathTool(),
    StructuredSearchTool(),
  ])
  .transport(.stdio)
  .run()
```

`tools/list` returns three entries (`weather`, `math`, `structuredSearch`), each with its own inlined input schema. `tools/call` dispatches on `params.name` — there's no shared state, no ordering coupling, and nothing else to wire.

## See also

- [`swift-ai-hub/docs/Macros.md`](https://github.com/mehmetbaykar/swift-ai-hub/blob/main/docs/Macros.md) — hub tool authoring reference.
- [`swift-ai-hub/docs/05-tools-dual-use.md`](../../swift-ai-hub/docs/05-tools-dual-use.md) — exposing the same tool to MCP and to an LLM session.
- [`swift-ai-hub/docs/06-mcp-bridge.md`](../../swift-ai-hub/docs/06-mcp-bridge.md) — file-by-file bridge contracts.
- `Sources/FastMCPAIBridge/` — the bridge adapter, mappers, registrar, and errors this document describes.
