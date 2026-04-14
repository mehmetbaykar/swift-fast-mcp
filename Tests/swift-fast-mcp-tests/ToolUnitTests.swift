import ExampleTools
import MCP
import MCPToolkit
import Testing

@testable import FastMCP

private func textContent(_ text: String) -> Tool.Content {
  .text(text: text, annotations: nil, _meta: nil)
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
    #expect(prompt.description!.contains("greeting"))
  }

  @Test
  func promptHasArguments() {
    let sdkPrompt = prompt.toPrompt()
    #expect(sdkPrompt.arguments != nil)
    #expect(sdkPrompt.arguments!.count == 2)
    #expect(sdkPrompt.arguments!.contains { $0.name == "name" })
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
  func returnsInformalMessagesWhenFormalIsFalse() async throws {
    let messages = try await prompt.getMessages(
      arguments: GreetingPrompt.Arguments(name: "Charlie", formal: false)
    )
    #expect(messages.count == 2)
  }
}

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
    #expect(result.content == [textContent("Result: 8.0")])
  }

  @Test
  func subtractOperationReturnsCorrectResult() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("subtract"),
      "a": .double(10),
      "b": .double(3),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Result: 7.0")])
  }

  @Test
  func multiplyOperationReturnsCorrectResult() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("multiply"),
      "a": .double(4),
      "b": .double(5),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Result: 20.0")])
  }

  @Test
  func divideOperationReturnsCorrectResult() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("divide"),
      "a": .double(20),
      "b": .double(4),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Result: 5.0")])
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

  @Test
  func additionWithNegativeNumbers() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("add"),
      "a": .double(-5),
      "b": .double(-3),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Result: -8.0")])
  }

  @Test
  func multiplicationByZero() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("multiply"),
      "a": .double(100),
      "b": .double(0),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Result: 0.0")])
  }

  @Test
  func divisionWithDecimalResult() async throws {
    let result = try await tool.call(arguments: [
      "operation": .string("divide"),
      "a": .double(7),
      "b": .double(2),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Result: 3.5")])
  }
}

@Suite("WeatherTool Unit Tests")
struct WeatherToolUnitTests {

  let tool = WeatherTool()

  @Test
  func toolHasCorrectName() {
    #expect(tool.name == "get_weather")
  }

  @Test
  func toolHasDescription() {
    #expect(tool.description != nil)
    #expect(tool.description!.contains("weather"))
  }

  @Test
  func returnsCelsiusByDefault() async throws {
    let result = try await tool.call(arguments: [
      "location": .string("Tokyo")
    ])
    #expect(result.isError != true)

    switch result.content.first {
    case .some(.text(text: let text, annotations: _, _meta: _)):
      #expect(text.contains("Tokyo"))
      #expect(text.contains("22°C"))
    default:
      Issue.record("Expected text content")
    }
  }

  @Test
  func returnsCelsiusWhenExplicitlyRequested() async throws {
    let result = try await tool.call(arguments: [
      "location": .string("Paris"),
      "unit": .string("celsius"),
    ])
    #expect(result.isError != true)

    switch result.content.first {
    case .some(.text(text: let text, annotations: _, _meta: _)):
      #expect(text.contains("22°C"))
    default:
      Issue.record("Expected text content")
    }
  }

  @Test
  func returnsFahrenheitWhenRequested() async throws {
    let result = try await tool.call(arguments: [
      "location": .string("New York"),
      "unit": .string("fahrenheit"),
    ])
    #expect(result.isError != true)

    switch result.content.first {
    case .some(.text(text: let text, annotations: _, _meta: _)):
      #expect(text.contains("New York"))
      #expect(text.contains("72°F"))
    default:
      Issue.record("Expected text content")
    }
  }

  @Test
  func includesWeatherCondition() async throws {
    let result = try await tool.call(arguments: [
      "location": .string("London")
    ])
    #expect(result.isError != true)

    switch result.content.first {
    case .some(.text(text: let text, annotations: _, _meta: _)):
      #expect(text.contains("Sunny"))
    default:
      Issue.record("Expected text content")
    }
  }
}

@Suite("GreetingTool Unit Tests")
struct GreetingToolUnitTests {

  let tool = GreetingTool()

  @Test
  func toolHasCorrectName() {
    #expect(tool.name == "greet")
  }

  @Test
  func toolHasDescription() {
    #expect(tool.description != nil)
    #expect(tool.description!.contains("greeting"))
  }

  @Test
  func returnsInformalGreetingByDefault() async throws {
    let result = try await tool.call(arguments: [
      "name": .string("Alice")
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Hey Alice!")])
  }

  @Test
  func returnsFormalGreetingWhenTrue() async throws {
    let result = try await tool.call(arguments: [
      "name": .string("Bob"),
      "formal": .bool(true),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Good day, Bob.")])
  }

  @Test
  func returnsInformalGreetingWhenFormalIsFalse() async throws {
    let result = try await tool.call(arguments: [
      "name": .string("Charlie"),
      "formal": .bool(false),
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Hey Charlie!")])
  }

  @Test
  func handlesSpecialCharactersInName() async throws {
    let result = try await tool.call(arguments: [
      "name": .string("José María")
    ])
    #expect(result.isError != true)
    #expect(result.content == [textContent("Hey José María!")])
  }
}

@Suite("StructuredSearchTool Unit Tests")
struct StructuredSearchToolUnitTests {

  let tool = StructuredSearchTool()

  @Test
  func toolPublishesOutputSchema() {
    let sdkTool = tool.toTool()
    #expect(sdkTool.name == "structured_search")
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
    #expect(result.content == [textContent("Query cannot be empty")])
    #expect(result.structuredContent == nil)
  }
}
