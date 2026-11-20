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

  @Test
  func `nil optional members are omitted from structuredContent at every object depth`() async throws {
    let adapter = try HubToolAdapter(tools: [OptionalFieldsTool()])
    let result = try await adapter.callTool(
      name: "optionalFields",
      arguments: .object(["includeOptionals": .bool(false)]),
      meta: nil
    )

    #expect(result.isError != true)
    #expect(result.content.count == 1)
    guard case .text = result.content.first else {
      Issue.record("Expected one JSON text block, got \(String(describing: result.content.first))")
      return
    }

    guard case .object(let structured) = result.structuredContent else {
      Issue.record(
        "Expected object structuredContent, got \(String(describing: result.structuredContent))")
      return
    }

    #expect(structured["required"] == .string("present"))
    #expect(structured["note"] == nil)
    #expect(structured["maybeInner"] == nil)
    #expect(Set(structured.keys) == Set(["required", "nested", "items"]))

    guard case .object(let nested) = structured["nested"] else {
      Issue.record("Expected nested object, got \(String(describing: structured["nested"]))")
      return
    }
    #expect(nested["title"] == .string("nested-title"))
    #expect(nested["hint"] == nil)
    #expect(Set(nested.keys) == Set(["title"]))

    guard case .array(let items) = structured["items"], items.count == 1 else {
      Issue.record("Expected one-item array, got \(String(describing: structured["items"]))")
      return
    }
    guard case .object(let item) = items[0] else {
      Issue.record("Expected object array element, got \(String(describing: items[0]))")
      return
    }
    #expect(item["title"] == .string("item-title"))
    #expect(item["hint"] == nil)
    #expect(Set(item.keys) == Set(["title"]))

    #expect(nullObjectMemberPaths(in: .object(structured)).isEmpty)
  }

  @Test
  func `non-nil optional members are present in structuredContent`() async throws {
    let adapter = try HubToolAdapter(tools: [OptionalFieldsTool()])
    let result = try await adapter.callTool(
      name: "optionalFields",
      arguments: .object(["includeOptionals": .bool(true)]),
      meta: nil
    )

    #expect(result.isError != true)
    #expect(result.content.count == 1)
    guard case .text = result.content.first else {
      Issue.record("Expected one JSON text block, got \(String(describing: result.content.first))")
      return
    }

    guard case .object(let structured) = result.structuredContent else {
      Issue.record(
        "Expected object structuredContent, got \(String(describing: result.structuredContent))")
      return
    }

    #expect(structured["required"] == .string("present"))
    #expect(structured["note"] == .string("a note"))
    #expect(Set(structured.keys) == Set(["required", "note", "maybeInner", "nested", "items"]))

    guard case .object(let maybeInner) = structured["maybeInner"] else {
      Issue.record("Expected maybeInner object, got \(String(describing: structured["maybeInner"]))")
      return
    }
    #expect(maybeInner["label"] == .string("inner-label"))

    guard case .object(let nested) = structured["nested"] else {
      Issue.record("Expected nested object, got \(String(describing: structured["nested"]))")
      return
    }
    #expect(nested["title"] == .string("nested-title"))
    #expect(nested["hint"] == .string("nested-hint"))

    guard case .array(let items) = structured["items"], items.count == 1,
      case .object(let item) = items[0]
    else {
      Issue.record("Expected one object item, got \(String(describing: structured["items"]))")
      return
    }
    #expect(item["title"] == .string("item-title"))
    #expect(item["hint"] == .string("item-hint"))
  }
}

// MARK: - Optional-field fixtures

@Generable
private struct OptionalInner {
  var label: String
}

@Generable
private struct NestedWithOptional {
  var title: String
  var hint: String?
}

@Generable
private struct OptionalFieldsOutput {
  var required: String
  var note: String?
  var maybeInner: OptionalInner?
  var nested: NestedWithOptional
  var items: [NestedWithOptional]
}

private struct OptionalFieldsTool: SwiftAIHub.Tool {
  let name = "optionalFields"
  let description = "Returns a Generable output with optional fields."

  @Generable
  struct Arguments {
    var includeOptionals: Bool
  }

  func call(arguments: Arguments) async throws -> OptionalFieldsOutput {
    if arguments.includeOptionals {
      return OptionalFieldsOutput(
        required: "present",
        note: "a note",
        maybeInner: OptionalInner(label: "inner-label"),
        nested: NestedWithOptional(title: "nested-title", hint: "nested-hint"),
        items: [NestedWithOptional(title: "item-title", hint: "item-hint")]
      )
    }
    return OptionalFieldsOutput(
      required: "present",
      note: nil,
      maybeInner: nil,
      nested: NestedWithOptional(title: "nested-title", hint: nil),
      items: [NestedWithOptional(title: "item-title", hint: nil)]
    )
  }
}

/// Paths of object members whose value is `.null` (array null elements are ignored).
private func nullObjectMemberPaths(in value: Value, path: String = "$") -> [String] {
  switch value {
  case .object(let fields):
    var paths: [String] = []
    for (key, child) in fields {
      let childPath = "\(path).\(key)"
      if case .null = child {
        paths.append(childPath)
      } else {
        paths.append(contentsOf: nullObjectMemberPaths(in: child, path: childPath))
      }
    }
    return paths
  case .array(let items):
    return items.enumerated().flatMap { index, child in
      nullObjectMemberPaths(in: child, path: "\(path)[\(index)]")
    }
  default:
    return []
  }
}
