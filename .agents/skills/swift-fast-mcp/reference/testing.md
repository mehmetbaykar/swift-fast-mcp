# Testing Patterns

All tests use Swift Testing (`import Testing`), not XCTest.

## Unit Testing Tools

Test tools directly by calling `call(arguments:)` with a dictionary:

```swift
import ExampleTools
import MCP
import MCPToolkit
import Testing

@testable import FastMCP

private func textContent(_ text: String) -> Tool.Content {
  .text(text: text, annotations: nil, _meta: nil)
}

@Suite("MathTool Unit Tests")
struct MathToolUnitTests {
  let tool = MathTool()

  @Test
  func addOperationReturnsCorrectResult() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("add"),
      "a": .double(5),
      "b": .double(3),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Result: 8.0")])
  }

  @Test
  func divisionByZeroReturnsError() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("divide"),
      "a": .double(10),
      "b": .double(0),
    ])
    #expect(result.isError == true)
  }
}
```

### Key Patterns

- Call `tool.call(arguments:)` with a `[String: MCP.Value]` dictionary
- String values: `.string("value")`
- Number values: `.double(5)` or `.int(5)` as appropriate
- Boolean values: `.bool(true)`
- Check `result.isError != true` for success, `result.isError == true` for error
- For exact content equality, compare against `.text(text: ..., annotations: nil, _meta: nil)`
- For flexible assertions, pattern-match the text payload:

```swift
switch result.content.first {
case .some(.text(text: let text, annotations: _, _meta: _)):
  #expect(text.contains("expected"))
default:
  Issue.record("Expected text content")
}
```

## Unit Testing Structured Tools

Structured tools can assert both content and `structuredContent`:

```swift
@Suite("StructuredSearchTool Unit Tests")
struct StructuredSearchToolUnitTests {
  let tool = StructuredSearchTool()

  @Test
  func publishesOutputSchema() {
    let sdkTool = tool.toTool()
    #expect(sdkTool.outputSchema != nil)
  }

  @Test
  func returnsContentAndStructuredContent() async throws {
    let result = try await tool.call(arguments: [
      "query": .string("swift")
    ])

    #expect(result.isError != true)
    #expect(result.content == [textContent("Found 2 results for swift")])
    #expect(
      result.structuredContent
        == .object([
          "summary": .string("Found 2 results for swift"),
          "resultCount": .int(2),
        ])
    )
  }

  @Test
  func returnsErrorWithoutStructuredContent() async throws {
    let result = try await tool.call(arguments: [
      "query": .string("")
    ])

    #expect(result.isError == true)
    #expect(result.structuredContent == nil)
  }
}
```

## Unit Testing Prompts

Test prompts by calling `getMessages(arguments:)` with typed arguments:

```swift
@Suite("GreetingPrompt Unit Tests")
struct GreetingPromptUnitTests {
  let prompt = GreetingPrompt()

  @Test
  func returnsFormalMessagesWhenRequested() async throws {
    let messages = try await prompt.getMessages(
      arguments: GreetingPrompt.Arguments(name: "Bob", formal: true)
    )
    #expect(messages.count == 2)
  }

  @Test
  func promptHasArguments() {
    let sdkPrompt = prompt.toPrompt()
    #expect(sdkPrompt.arguments?.count == 2)
  }
}
```

## Integration Testing with InMemoryTransport

Use `.transport(.inMemory)` to test builder configuration without I/O:

```swift
@Suite("Integration Tests")
struct IntegrationTests {
  @Test
  func serverStartsWithInMemoryTransport() async throws {
    let builder = FastMCP.builder()
      .name("TestServer")
      .addTools([GreetingTool(), StructuredSearchTool()])
      .transport(.inMemory)

    guard case .inMemory = builder.transportConfig else {
      Issue.record("Expected inMemory transport")
      return
    }
    #expect(builder.tools.count == 2)
  }
}
```

## Testing Builder Configuration

```swift
@Suite("FastMCP Builder Tests")
struct BuilderTests {
  @Test
  func builderChainWorksWithAllOptions() {
    var logger = Logger(label: "TestServer")
    logger.logLevel = .warning

    let builder = FastMCP.builder()
      .name("TestServer")
      .version("3.0.0")
      .addTools([GreetingTool(), StructuredSearchTool()])
      .addPrompts([GreetingPrompt()])
      .enableCompletions()
      .enableLogging()
      .transport(.stdio)
      .logger(logger)
      .shutdownSignals([.sigterm])
      .onInitialize { _, _ in }
      .onStart {}
      .onShutdown {}

    #expect(builder.tools.count == 2)
    #expect(builder.prompts.count == 1)
    #expect(builder.completionsEnabled == true)
    #expect(builder.loggingEnabled == true)
    #expect(builder.customLogger != nil)
  }
}
```

## Test Target Setup

In `Package.swift`, the test target depends on both `FastMCP` and your library target:

```swift
.testTarget(
  name: "MyServerTests",
  dependencies: ["FastMCP", "MyServerLib"]
)
```
