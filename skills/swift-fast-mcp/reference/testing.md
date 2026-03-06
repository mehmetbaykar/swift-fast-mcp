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

@Suite("MathTool Unit Tests")
struct MathToolUnitTests {

  let tool = MathTool()

  @Test
  func toolHasCorrectName() {
    #expect(tool.name == "calculate")
  }

  @Test
  func toolHasDescription() {
    #expect(tool.description != nil)
    #expect(tool.description!.contains("math"))
  }

  @Test
  func addOperationReturnsCorrectResult() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("add"),
      "a": .double(5),
      "b": .double(3),
    ])
    #expect(result.isError != true)
    #expect(result.content == [.text("Result: 8.0")])
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

- Call `tool.call(arguments:)` with a `[String: JSONValue]` dictionary
- String values: `.string("value")`
- Number values: `.double(5)`
- Boolean values: `.bool(true)`
- Check `result.isError != true` for success, `result.isError == true` for error
- Compare content directly: `result.content == [.text("expected")]`
- Use pattern matching for complex content assertions:

```swift
switch result.content.first {
case .some(.text(let text)):
  #expect(text.contains("expected"))
default:
  Issue.record("Expected text content")
}
```

## Unit Testing Prompts

Test prompts by calling `getMessages(arguments:)` with typed arguments:

```swift
@Suite("GreetingPrompt Unit Tests")
struct GreetingPromptUnitTests {

  let prompt = GreetingPrompt()

  @Test
  func promptHasCorrectName() {
    #expect(prompt.name == "greeting")
  }

  @Test
  func returnsInformalMessagesWithName() async throws {
    let messages = try await prompt.getMessages(
      arguments: GreetingPrompt.Arguments(name: "Alice", formal: nil)
    )
    #expect(messages.count == 2)
  }

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
    #expect(sdkPrompt.arguments != nil)
    #expect(sdkPrompt.arguments!.count == 2)
    #expect(sdkPrompt.arguments!.contains { $0.name == "name" })
  }
}
```

## Integration Testing with InMemoryTransport

Use `.transport(.inMemory)` to test full MCP request/response flow without I/O:

```swift
@Suite("Integration Tests")
struct IntegrationTests {

  @Test
  func serverStartsWithInMemoryTransport() async throws {
    let builder = FastMCP.builder()
      .name("TestServer")
      .version("1.0.0")
      .addTools([GreetingTool()])
      .transport(.inMemory)

    // Verify builder configuration
    guard case .inMemory = builder.transportConfig else {
      Issue.record("Expected inMemory transport")
      return
    }
    #expect(builder.tools.count == 1)
  }
}
```

## Testing Builder Configuration

```swift
@Suite("FastMCP Builder Tests")
struct BuilderTests {

  @Test
  func builderUsesDefaultValues() {
    let builder = FastMCP.builder()
    #expect(builder.serverVersion == "1.0.0")
    #expect(builder.tools.isEmpty)
    #expect(builder.resources.isEmpty)
    #expect(builder.prompts.isEmpty)
    #expect(builder.samplingEnabled == false)
  }

  @Test
  func builderChainWorksWithAllOptions() {
    var logger = Logger(label: "TestServer")
    logger.logLevel = .warning

    let builder = FastMCP.builder()
      .name("TestServer")
      .version("3.0.0")
      .addTools([GreetingTool()])
      .addPrompts([GreetingPrompt()])
      .enableSampling()
      .transport(.stdio)
      .logger(logger)
      .shutdownSignals([.sigterm])
      .onStart {}
      .onShutdown {}

    #expect(builder.serverName == "TestServer")
    #expect(builder.serverVersion == "3.0.0")
    #expect(builder.tools.count == 1)
    #expect(builder.prompts.count == 1)
    #expect(builder.samplingEnabled == true)
    #expect(builder.customLogger != nil)
  }

  @Test
  func builderCreatesNewInstanceOnEachMethod() {
    let original = FastMCP.builder().name("Original")
    let modified = original.name("Modified")
    #expect(original.serverName == "Original")
    #expect(modified.serverName == "Modified")
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

Use `@testable import FastMCP` to access internal builder properties in tests.

## Swift Testing Quick Reference

- `@Suite("Name")` — test suite annotation
- `@Test` — test function annotation
- `#expect(condition)` — assertion
- `Issue.record("message")` — record a test failure
- `import Testing` — required import (not XCTest)
