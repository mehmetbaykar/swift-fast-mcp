// swift-fast-mcp — FastMCPAIBridge tests
// tools/list must publish hub ToolAnnotations as MCP title + behavior hints.

import FastMCPAIBridge
import Foundation
import SwiftAIHub
import Testing

import struct MCP.Tool

// MARK: - Fixtures

@Tool("A tool with no title or hints.")
private struct PlainAnnotationTool {
  @Generable
  struct Arguments {}

  func execute(_ arguments: Arguments) async throws -> String { "ok" }
}

@Tool("Search the docs", title: "Search Docs", readOnly: true)
private struct TitledReadOnlyTool {
  @Generable
  struct Arguments {}

  func execute(_ arguments: Arguments) async throws -> String { "ok" }
}

@Tool(
  "Mixed hint tool",
  title: "Mixed Hints",
  readOnly: true,
  destructive: false,
  idempotent: true,
  openWorld: false
)
private struct MixedHintsTool {
  @Generable
  struct Arguments {}

  func execute(_ arguments: Arguments) async throws -> String { "ok" }
}

private struct HandWrittenAnnotatedTool: SwiftAIHub.Tool {
  let name = "hand_written_annotated"
  let description = "Hand-written Tool with explicit annotations."
  var annotations: ToolAnnotations {
    ToolAnnotations(title: "Hand Written", readOnly: true, openWorld: false)
  }

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> String { "ok" }
}

// MARK: - Helpers

private func encodedToolJSON(_ tool: MCP.Tool) throws -> [String: Any] {
  let data = try JSONEncoder().encode(tool)
  let object = try JSONSerialization.jsonObject(with: data)
  guard let dictionary = object as? [String: Any] else {
    Issue.record("Expected JSON object, got \(object)")
    return [:]
  }
  return dictionary
}

// MARK: - Tests

@Suite("HubToolMapper annotations")
struct HubToolMapperAnnotationsTests {

  @Test
  func `tool without annotations omits title and annotations keys`() throws {
    let mapped = HubToolMapper.mapTool(PlainAnnotationTool())
    let json = try encodedToolJSON(mapped)

    #expect(json["title"] == nil)
    #expect(json["annotations"] == nil)
  }

  @Test
  func `title and readOnly publish only those wire fields`() throws {
    let mapped = HubToolMapper.mapTool(TitledReadOnlyTool())
    let json = try encodedToolJSON(mapped)

    #expect(json["title"] as? String == "Search Docs")
    let annotations = try #require(json["annotations"] as? [String: Any])
    #expect(annotations["readOnlyHint"] as? Bool == true)
    #expect(annotations["title"] == nil)
    #expect(annotations.keys.sorted() == ["readOnlyHint"])
  }

  @Test
  func `all four hints encode with MCP key names`() throws {
    let mapped = HubToolMapper.mapTool(MixedHintsTool())
    let json = try encodedToolJSON(mapped)

    #expect(json["title"] as? String == "Mixed Hints")
    let annotations = try #require(json["annotations"] as? [String: Any])
    #expect(annotations["readOnlyHint"] as? Bool == true)
    #expect(annotations["destructiveHint"] as? Bool == false)
    #expect(annotations["idempotentHint"] as? Bool == true)
    #expect(annotations["openWorldHint"] as? Bool == false)
    #expect(annotations["title"] == nil)
    #expect(
      Set(annotations.keys)
        == Set(["readOnlyHint", "destructiveHint", "idempotentHint", "openWorldHint"])
    )
  }

  @Test
  func `hand-written Tool annotations are published the same way`() throws {
    let mapped = HubToolMapper.mapTool(HandWrittenAnnotatedTool())
    let json = try encodedToolJSON(mapped)

    #expect(json["title"] as? String == "Hand Written")
    let annotations = try #require(json["annotations"] as? [String: Any])
    #expect(annotations["readOnlyHint"] as? Bool == true)
    #expect(annotations["openWorldHint"] as? Bool == false)
    #expect(annotations["title"] == nil)
    #expect(Set(annotations.keys) == Set(["readOnlyHint", "openWorldHint"]))
  }

  @Test
  func `HubToolAdapter listTools publishes title and annotations`() async throws {
    let adapter = try HubToolAdapter(tools: [TitledReadOnlyTool()])
    let listed = await adapter.listTools()
    let tool = try #require(listed.first)
    let json = try encodedToolJSON(tool)

    #expect(json["title"] as? String == "Search Docs")
    let annotations = try #require(json["annotations"] as? [String: Any])
    #expect(annotations["readOnlyHint"] as? Bool == true)
    #expect(annotations.keys.sorted() == ["readOnlyHint"])
  }
}
