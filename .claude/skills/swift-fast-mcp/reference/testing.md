# Testing Patterns

All tests use Swift Testing (`import Testing`), not XCTest. The patterns
below mirror `Tests/swift-fast-mcp-tests/ToolUnitTests.swift`,
`Tests/swift-fast-mcp-tests/BuilderTests.swift`, and
`Tests/swift-fast-mcp-tests/MCPPromptMacroTests.swift`.

## Tools — through the bridge

Tools are exposed to MCP via `HubToolAdapter` (the same path
`tools/call` uses). Round-trip a tool through the adapter and assert on the
`GeneratedContent` it produces.

```swift
import ExampleTools
import FastMCPAIBridge
import MCP
import Testing

@testable import FastMCP

private func execute(
  _ tool: any SwiftAIHub.Tool,
  arguments: [String: Value]
) async throws -> GeneratedContent {
  let adapter = try HubToolAdapter(tools: [tool])
  return try await adapter.execute(name: tool.name, arguments: .object(arguments))
}

@Suite("MathTool Unit Tests")
struct MathToolUnitTests {
  let tool = MathTool()

  @Test func `tool has correct name`() {
    #expect(tool.name == "math")
  }

  @Test func `add operation returns correct result`() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("add"), "a": .double(5), "b": .double(3)]
    )
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string GeneratedContent, got \(content.kind)")
      return
    }
    #expect(text == "Result: 8.0")
  }

  @Test func `division by zero throws`() async throws {
    await #expect(throws: HubBridgeError.self) {
      _ = try await execute(
        tool,
        arguments: ["operation": .string("divide"), "a": .double(10), "b": .double(0)]
      )
    }
  }
}
```

Notes:

- MCP argument values use the `MCP.Value` cases: `.string`, `.double`,
  `.int`, `.bool`, `.object`, `.array`, `.null`.
- Errors thrown from `execute(_:)` surface through the bridge as
  `HubBridgeError.invalidArguments(...)`. Assert with
  `#expect(throws: HubBridgeError.self)`.
- For tools that return a `@Generable` type, the bridge emits
  `.structure(...)` instead of `.string(...)`:

```swift
@Test func `returns structured content`() async throws {
  let content = try await execute(StructuredSearchTool(), arguments: ["query": .string("swift")])
  guard case .structure(let properties, _) = content.kind else {
    Issue.record("Expected structured GeneratedContent, got \(content.kind)")
    return
  }
  #expect(properties["resultCount"]?.jsonString == "2")
}
```

## Tools — schema assertions

`HubToolMapper.mapTool(_:)` produces the `MCP.Tool` published to
`tools/list`. Assert on its `inputSchema` to lock in the wire shape:

```swift
@Test func `bridge publishes tool description`() {
  let mapped = HubToolMapper.mapTool(StructuredSearchTool())
  #expect(mapped.name == "structuredSearch")
  guard case .object(let fields) = mapped.inputSchema else {
    Issue.record("Expected object input schema")
    return
  }
  #expect(fields["type"] == .string("object"))
}
```

## Prompts

Prompts decode arguments out of a raw `[String: String]` dictionary —
that is the wire format on `prompts/get`. Assert by calling
`getMessages(arguments:)` directly:

```swift
@Suite("GreetingPrompt Unit Tests")
struct GreetingPromptUnitTests {
  let prompt = GreetingPrompt()

  @Test func `prompt has correct name`() {
    #expect(prompt.name == "greeting")
  }

  @Test func `prompt exposes argument specs`() {
    #expect(prompt.arguments.count == 2)
    #expect(prompt.arguments.contains { $0.name == "name" })
    #expect(prompt.arguments.contains { $0.name == "tone" })
  }

  @Test func `returns formal messages when requested`() async throws {
    let messages = try await prompt.getMessages(arguments: ["name": "Bob", "tone": "formal"])
    #expect(messages.count == 2)
  }
}
```

## Resources

For a static resource, evaluate `content` and inspect the
`ResourceContentItem` array:

```swift
@Test func `config resource returns json`() async throws {
  let resource = ConfigResource()
  let items = try await resource.content
  #expect(!items.isEmpty)
}
```

## Builder configuration

The builder is a value type, so assertions read its stored properties via
`@testable import FastMCP`:

```swift
@Test func `builder accumulates tools across calls`() throws {
  let builder = try FastMCP.builder()
    .name("TestServer")
    .addTools([WeatherTool()])
    .addTools([MathTool()])
  #expect(builder.hubTools.count == 2)
}
```

## Test target setup

```swift
.testTarget(
  name: "MyServerTests",
  dependencies: [
    .product(name: "FastMCP", package: "swift-fast-mcp"),
    .product(name: "FastMCPAIBridge", package: "swift-fast-mcp"),
    "MyServerLib",
  ]
)
```

`FastMCPAIBridge` is the public library that exposes `HubToolAdapter` and
`HubToolMapper` for round-trip tests. `import FastMCP` re-exports
`SwiftAIHub`, so a generated package does not need a direct swift-ai-hub
dependency to reference `SwiftAIHub.Tool`.
