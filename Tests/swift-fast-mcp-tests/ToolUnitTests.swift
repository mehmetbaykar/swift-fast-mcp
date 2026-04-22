import ExampleTools
import FastMCPAIBridge
import MCP
import SwiftAIHub
import Testing

@testable import FastMCP

// Round-trips a tool through HubToolAdapter, returning the GeneratedContent the
// bridge would emit to a connected MCP client.
private func execute(
  _ tool: any SwiftAIHub.Tool,
  arguments: [String: Value]
) async throws -> GeneratedContent {
  let adapter = HubToolAdapter(tools: [tool])
  return try await adapter.execute(name: tool.name, arguments: .object(arguments))
}

private func expectString(_ content: GeneratedContent, _ expected: String) {
  guard case .string(let text) = content.kind else {
    Issue.record("Expected string GeneratedContent, got \(content.kind)")
    return
  }
  #expect(text == expected)
}

@Suite("GreetingPrompt Unit Tests")
struct GreetingPromptUnitTests {

  let prompt = GreetingPrompt()

  @Test
  func promptHasCorrectName() {
    #expect(prompt.name == "greeting")
  }

  @Test
  func promptHasDescription() {
    #expect(prompt.description != nil)
    #expect(prompt.description?.contains("greeting") == true)
  }

  @Test
  func promptExposesArgumentSpecs() {
    #expect(prompt.arguments.count == 2)
    #expect(prompt.arguments.contains { $0.name == "name" })
    #expect(prompt.arguments.contains { $0.name == "formal" })
  }

  @Test
  func returnsInformalMessagesWithName() async throws {
    let messages = try await prompt.getMessages(arguments: ["name": "Alice"])
    #expect(messages.count == 2)
  }

  @Test
  func returnsFormalMessagesWhenRequested() async throws {
    let messages = try await prompt.getMessages(arguments: ["name": "Bob", "formal": "true"])
    #expect(messages.count == 2)
  }

  @Test
  func returnsInformalMessagesWhenFormalIsFalse() async throws {
    let messages = try await prompt.getMessages(arguments: ["name": "Charlie", "formal": "false"])
    #expect(messages.count == 2)
  }
}

@Suite("MathTool Unit Tests")
struct MathToolUnitTests {

  let tool = MathTool()

  @Test
  func toolHasCorrectName() {
    #expect(tool.name == "math")
  }

  @Test
  func toolHasDescription() {
    #expect(tool.description.contains("math"))
  }

  @Test
  func addOperationReturnsCorrectResult() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("add"), "a": .double(5), "b": .double(3)]
    )
    expectString(content, "Result: 8.0")
  }

  @Test
  func subtractOperationReturnsCorrectResult() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("subtract"), "a": .double(10), "b": .double(3)]
    )
    expectString(content, "Result: 7.0")
  }

  @Test
  func multiplyOperationReturnsCorrectResult() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("multiply"), "a": .double(4), "b": .double(5)]
    )
    expectString(content, "Result: 20.0")
  }

  @Test
  func divideOperationReturnsCorrectResult() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("divide"), "a": .double(20), "b": .double(4)]
    )
    expectString(content, "Result: 5.0")
  }

  @Test
  func divisionByZeroThrows() async throws {
    await #expect(throws: HubBridgeError.self) {
      _ = try await execute(
        tool,
        arguments: ["operation": .string("divide"), "a": .double(10), "b": .double(0)]
      )
    }
  }

  @Test
  func additionWithNegativeNumbers() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("add"), "a": .double(-5), "b": .double(-3)]
    )
    expectString(content, "Result: -8.0")
  }

  @Test
  func multiplicationByZero() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("multiply"), "a": .double(100), "b": .double(0)]
    )
    expectString(content, "Result: 0.0")
  }

  @Test
  func divisionWithDecimalResult() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("divide"), "a": .double(7), "b": .double(2)]
    )
    expectString(content, "Result: 3.5")
  }
}

@Suite("WeatherTool Unit Tests")
struct WeatherToolUnitTests {

  let tool = WeatherTool()

  @Test
  func toolHasCorrectName() {
    #expect(tool.name == "weather")
  }

  @Test
  func toolHasDescription() {
    #expect(tool.description.contains("weather"))
  }

  @Test
  func returnsCelsiusByDefault() async throws {
    let content = try await execute(tool, arguments: ["location": .string("Tokyo")])
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string content")
      return
    }
    #expect(text.contains("Tokyo"))
    #expect(text.contains("22°C"))
  }

  @Test
  func returnsCelsiusWhenExplicitlyRequested() async throws {
    let content = try await execute(
      tool,
      arguments: ["location": .string("Paris"), "unit": .string("celsius")]
    )
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string content")
      return
    }
    #expect(text.contains("22°C"))
  }

  @Test
  func returnsFahrenheitWhenRequested() async throws {
    let content = try await execute(
      tool,
      arguments: ["location": .string("New York"), "unit": .string("fahrenheit")]
    )
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string content")
      return
    }
    #expect(text.contains("New York"))
    #expect(text.contains("72°F"))
  }

  @Test
  func includesWeatherCondition() async throws {
    let content = try await execute(tool, arguments: ["location": .string("London")])
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string content")
      return
    }
    #expect(text.contains("Sunny"))
  }
}

@Suite("GreetingTool Unit Tests")
struct GreetingToolUnitTests {

  let tool = GreetingTool()

  @Test
  func toolHasCorrectName() {
    #expect(tool.name == "greeting")
  }

  @Test
  func toolHasDescription() {
    #expect(tool.description.contains("greeting"))
  }

  @Test
  func returnsInformalGreetingByDefault() async throws {
    let content = try await execute(tool, arguments: ["who": .string("Alice")])
    expectString(content, "Hey Alice!")
  }

  @Test
  func returnsFormalGreetingWhenTrue() async throws {
    let content = try await execute(
      tool,
      arguments: ["who": .string("Bob"), "formal": .bool(true)]
    )
    expectString(content, "Good day, Bob.")
  }

  @Test
  func returnsInformalGreetingWhenFormalIsFalse() async throws {
    let content = try await execute(
      tool,
      arguments: ["who": .string("Charlie"), "formal": .bool(false)]
    )
    expectString(content, "Hey Charlie!")
  }

  @Test
  func handlesSpecialCharactersInName() async throws {
    let content = try await execute(tool, arguments: ["who": .string("José María")])
    expectString(content, "Hey José María!")
  }
}

@Suite("StructuredSearchTool Unit Tests")
struct StructuredSearchToolUnitTests {

  let tool = StructuredSearchTool()

  @Test
  func bridgePublishesToolDescription() {
    let mapped = HubToolMapper.mapTool(tool)
    #expect(mapped.name == "structuredSearch")
    // HubToolMapper currently advertises a free-form object schema until the
    // generation-schema → JSON-schema work lands (task #9).
    guard case .object(let fields) = mapped.inputSchema else {
      Issue.record("Expected object input schema")
      return
    }
    #expect(fields["type"] == .string("object"))
  }

  @Test
  func returnsStructuredContent() async throws {
    let content = try await execute(tool, arguments: ["query": .string("swift")])
    guard case .structure(let properties, _) = content.kind else {
      Issue.record("Expected structured GeneratedContent, got \(content.kind)")
      return
    }
    #expect(properties["summary"]?.jsonString.contains("Found 2 results for swift") == true)
    #expect(properties["resultCount"]?.jsonString == "2")
  }

  @Test
  func emptyQueryThrowsThroughBridge() async throws {
    await #expect(throws: HubBridgeError.self) {
      _ = try await execute(tool, arguments: ["query": .string("")])
    }
  }
}
