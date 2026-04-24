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
  let adapter = try HubToolAdapter(tools: [tool])
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

  @Test func `prompt has correct name`() {
    #expect(prompt.name == "greeting")
  }

  @Test func `prompt has description`() {
    #expect(prompt.description != nil)
    #expect(prompt.description?.contains("greeting") == true)
  }

  @Test func `prompt exposes argument specs`() {
    #expect(prompt.arguments.count == 2)
    #expect(prompt.arguments.contains { $0.name == "name" })
    #expect(prompt.arguments.contains { $0.name == "tone" })
  }

  @Test func `returns casual messages with name`() async throws {
    let messages = try await prompt.getMessages(arguments: ["name": "Alice"])
    #expect(messages.count == 2)
  }

  @Test func `returns formal messages when requested`() async throws {
    let messages = try await prompt.getMessages(arguments: ["name": "Bob", "tone": "formal"])
    #expect(messages.count == 2)
  }

  @Test func `returns professional messages when requested`() async throws {
    let messages = try await prompt.getMessages(
      arguments: ["name": "Charlie", "tone": "professional"]
    )
    #expect(messages.count == 2)
  }
}

@Suite("MathTool Unit Tests")
struct MathToolUnitTests {

  let tool = MathTool()

  @Test func `tool has correct name`() {
    #expect(tool.name == "math")
  }

  @Test func `tool has description`() {
    #expect(tool.description.contains("math"))
  }

  @Test func `add operation returns correct result`() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("add"), "a": .double(5), "b": .double(3)]
    )
    expectString(content, "Result: 8.0")
  }

  @Test func `subtract operation returns correct result`() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("subtract"), "a": .double(10), "b": .double(3)]
    )
    expectString(content, "Result: 7.0")
  }

  @Test func `multiply operation returns correct result`() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("multiply"), "a": .double(4), "b": .double(5)]
    )
    expectString(content, "Result: 20.0")
  }

  @Test func `divide operation returns correct result`() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("divide"), "a": .double(20), "b": .double(4)]
    )
    expectString(content, "Result: 5.0")
  }

  @Test func `division by zero throws`() async throws {
    await #expect(throws: HubBridgeError.self) {
      _ = try await execute(
        tool,
        arguments: ["operation": .string("divide"), "a": .double(10), "b": .double(0)]
      )
    }
  }

  @Test func `addition with negative numbers`() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("add"), "a": .double(-5), "b": .double(-3)]
    )
    expectString(content, "Result: -8.0")
  }

  @Test func `multiplication by zero`() async throws {
    let content = try await execute(
      tool,
      arguments: ["operation": .string("multiply"), "a": .double(100), "b": .double(0)]
    )
    expectString(content, "Result: 0.0")
  }

  @Test func `division with decimal result`() async throws {
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

  @Test func `tool has correct name`() {
    #expect(tool.name == "weather")
  }

  @Test func `tool has description`() {
    #expect(tool.description.contains("weather"))
  }

  private func coordinateValue(latitude: Double, longitude: Double) -> Value {
    .object(["latitude": .double(latitude), "longitude": .double(longitude)])
  }

  @Test func `returns celsius when explicitly requested`() async throws {
    let content = try await execute(
      tool,
      arguments: [
        "coordinate": coordinateValue(latitude: 48.85, longitude: 2.35),
        "unit": .string("celsius"),
      ]
    )
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string content")
      return
    }
    #expect(text.contains("22°C"))
  }

  @Test func `returns fahrenheit when requested`() async throws {
    let content = try await execute(
      tool,
      arguments: [
        "coordinate": coordinateValue(latitude: 40.71, longitude: -74.0),
        "unit": .string("fahrenheit"),
      ]
    )
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string content")
      return
    }
    #expect(text.contains("40.71"))
    #expect(text.contains("72°F"))
  }

  @Test func `includes weather condition`() async throws {
    let content = try await execute(
      tool,
      arguments: [
        "coordinate": coordinateValue(latitude: 51.5, longitude: -0.12),
        "unit": .string("celsius"),
      ]
    )
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

  @Test func `tool has correct name`() {
    #expect(tool.name == "greeting")
  }

  @Test func `tool has description`() {
    #expect(tool.description.contains("greeting"))
  }

  private func personValue(firstName: String, lastName: String? = nil) -> Value {
    var fields: [String: Value] = ["firstName": .string(firstName)]
    if let lastName { fields["lastName"] = .string(lastName) }
    return .object(fields)
  }

  @Test func `returns casual greeting`() async throws {
    let content = try await execute(
      tool,
      arguments: [
        "person": personValue(firstName: "Alice"),
        "tone": .string("casual"),
      ]
    )
    expectString(content, "Hey Alice!")
  }

  @Test func `returns formal greeting when requested`() async throws {
    let content = try await execute(
      tool,
      arguments: ["person": personValue(firstName: "Bob"), "tone": .string("formal")]
    )
    expectString(content, "Good day, Bob.")
  }

  @Test func `returns professional greeting when requested`() async throws {
    let content = try await execute(
      tool,
      arguments: [
        "person": personValue(firstName: "Charlie", lastName: "Brown"),
        "tone": .string("professional"),
      ]
    )
    expectString(content, "Hello Charlie Brown, how can I help you today?")
  }

  @Test func `handles special characters in name`() async throws {
    let content = try await execute(
      tool,
      arguments: [
        "person": personValue(firstName: "José", lastName: "María"),
        "tone": .string("casual"),
      ]
    )
    expectString(content, "Hey José María!")
  }
}

@Suite("StructuredSearchTool Unit Tests")
struct StructuredSearchToolUnitTests {

  let tool = StructuredSearchTool()

  @Test func `bridge publishes tool description`() {
    let mapped = HubToolMapper.mapTool(tool)
    #expect(mapped.name == "structuredSearch")
    guard case .object(let fields) = mapped.inputSchema else {
      Issue.record("Expected object input schema")
      return
    }
    #expect(fields["type"] == .string("object"))
    guard case .object(let properties) = fields["properties"] ?? .null else {
      Issue.record("Expected properties object")
      return
    }
    #expect(properties["query"]?.objectValue?["type"] == .string("string"))
  }

  @Test func `returns structured content`() async throws {
    let content = try await execute(tool, arguments: ["query": .string("swift")])
    guard case .structure(let properties, _) = content.kind else {
      Issue.record("Expected structured GeneratedContent, got \(content.kind)")
      return
    }
    #expect(properties["summary"]?.jsonString.contains("Found 2 results for swift") == true)
    #expect(properties["resultCount"]?.jsonString == "2")
  }

  @Test func `empty query throws through bridge`() async throws {
    await #expect(throws: HubBridgeError.self) {
      _ = try await execute(tool, arguments: ["query": .string("")])
    }
  }
}
