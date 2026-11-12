// swift-fast-mcp — FastMCPAIBridge tests
// Coverage for structuredContent + outputSchema on native tool calls.

import ExampleTools
import FastMCPAIBridge
import Foundation
import SwiftAIHub
import Testing

// Fully qualify `MCP.Tool.Content` — importing MCP would make the @Generable
// macro's reference to `Prompt` ambiguous against `MCP.Prompt`.
import enum MCP.CallTool
import struct MCP.Tool
import enum MCP.Value

// MARK: - Fixture tools

private struct ArrayEchoTool: SwiftAIHub.Tool {
  let name = "arrayEcho"
  let description = "Returns a fixed string array."

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> [String] {
    ["one", "two"]
  }
}

private struct ObjectEchoTool: SwiftAIHub.Tool {
  let name = "objectEcho"
  let description = "Returns a fixed object payload via segments."

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> String { "unused" }

  func makeOutputSegments(from arguments: GeneratedContent) async throws -> [Transcript.Segment] {
    let content = GeneratedContent(
      kind: .structure(
        properties: [
          "summary": GeneratedContent(kind: .string("ok")),
          "resultCount": GeneratedContent(kind: .number(2)),
        ],
        orderedKeys: ["summary", "resultCount"]
      ))
    return [.structure(.init(source: name, content: content))]
  }
}

// MARK: - Tests

@Suite("HubToolAdapter structuredContent")
struct HubToolAdapterStructuredContentTests {

  @Test
  func `StructuredSearchTool lists object outputSchema and returns structuredContent`() async throws {
    let adapter = try HubToolAdapter(tools: [StructuredSearchTool()])

    let listed = await adapter.listTools()
    let tool = try #require(listed.first { $0.name == "structured_search" })
    guard case .object(let root) = tool.outputSchema else {
      Issue.record("Expected object outputSchema, got \(String(describing: tool.outputSchema))")
      return
    }
    #expect(root["type"] == .string("object"))
    guard case .object(let properties) = root["properties"] ?? .null else {
      Issue.record("Expected properties object")
      return
    }
    #expect(properties["summary"] != nil)
    #expect(properties["resultCount"] != nil)

    let result = try await adapter.callTool(
      name: "structured_search",
      arguments: .object(["query": .string("swift")]),
      meta: nil
    )

    #expect(result.isError != true)
    #expect(result.content.count == 1)
    guard case .text(let text, _, _) = result.content.first else {
      Issue.record("Expected one JSON text block, got \(String(describing: result.content.first))")
      return
    }
    #expect(text.contains("\"summary\""))
    #expect(text.contains("\"resultCount\""))

    guard case .object(let structured) = result.structuredContent else {
      Issue.record(
        "Expected object structuredContent, got \(String(describing: result.structuredContent))")
      return
    }
    #expect(structured["summary"] != nil)
    #expect(structured["resultCount"] != nil)
    #expect(Set(structured.keys) == Set(["summary", "resultCount"]))
  }

  @Test
  func `String and array tools have nil outputSchema and nil structuredContent`() async throws {
    let adapter = try HubToolAdapter(tools: [MathTool(), ArrayEchoTool()])

    let listed = await adapter.listTools()
    let math = try #require(listed.first { $0.name == "math" })
    let array = try #require(listed.first { $0.name == "arrayEcho" })
    #expect(math.outputSchema == nil)
    #expect(array.outputSchema == nil)

    let mathResult = try await adapter.callTool(
      name: "math",
      arguments: .object([
        "operation": .string("add"),
        "a": .double(1),
        "b": .double(2),
      ]),
      meta: nil
    )
    #expect(mathResult.structuredContent == nil)
    #expect(mathResult.isError != true)

    let arrayResult = try await adapter.callTool(
      name: "arrayEcho",
      arguments: .object([:]),
      meta: nil
    )
    #expect(arrayResult.structuredContent == nil)
    #expect(arrayResult.isError != true)
  }

  @Test
  func `error results have no structuredContent`() {
    let result = HubErrorMapper.mapCallToolError(
      HubBridgeError.toolNotFound("missing"),
      toolName: "missing"
    )
    #expect(result.isError == true)
    #expect(result.structuredContent == nil)
  }

  @Test
  func `object structure segment sets structuredContent alongside JSON text`() async throws {
    let adapter = try HubToolAdapter(tools: [ObjectEchoTool()])
    let result = try await adapter.callTool(
      name: "objectEcho",
      arguments: .object([:]),
      meta: nil
    )

    #expect(result.content.count == 1)
    guard case .text(let text, _, _) = result.content.first else {
      Issue.record("Expected JSON text content")
      return
    }
    #expect(text.contains("\"summary\""))

    guard case .object(let structured) = result.structuredContent else {
      Issue.record("Expected structuredContent object")
      return
    }
    #expect(structured["summary"] == .string("ok"))
    #expect(structured["resultCount"] == .int(2) || structured["resultCount"] == .double(2))
  }
}
