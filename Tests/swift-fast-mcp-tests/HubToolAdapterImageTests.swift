// swift-fast-mcp — FastMCPAIBridge tests
// Regression coverage for image + structured tool output passing through the
// MCP bridge as typed Tool.Content instead of being flattened to "[image]".

import FastMCP
import FastMCPAIBridge
import Foundation
import SwiftAIHub
import Testing

// Fully qualify `MCP.Tool.Content` in assertions — importing MCP here would
// make the @Generable macro's reference to `Prompt` ambiguous against
// `MCP.Prompt`.
import struct MCP.Tool
import enum MCP.Value

// MARK: - Fixture tools
//
// These tools override `makeOutputSegments(from:)` directly so they can emit
// the specific segment shape each test needs (image, structured, text) without
// routing through the default `String`/`ConvertibleToGeneratedContent` paths.

private struct ImageEchoTool: SwiftAIHub.Tool {
  let name = "imageEcho"
  let description = "Returns a fixed image payload for bridge tests."

  @Generable
  struct Arguments {}

  static let fixtureData = Data([0x89, 0x50, 0x4E, 0x47])
  static let fixtureMime = "image/png"

  func call(arguments: Arguments) async throws -> String { "unused" }

  func makeOutputSegments(from arguments: GeneratedContent) async throws -> [Transcript.Segment] {
    [.image(Transcript.ImageSegment(data: Self.fixtureData, mimeType: Self.fixtureMime))]
  }
}

private struct StructuredEchoTool: SwiftAIHub.Tool {
  let name = "structuredEcho"
  let description = "Returns a fixed structured payload."

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> String { "unused" }

  func makeOutputSegments(from arguments: GeneratedContent) async throws -> [Transcript.Segment] {
    let content = GeneratedContent(
      kind: .structure(
        properties: ["answer": GeneratedContent(kind: .number(42))],
        orderedKeys: ["answer"]
      ))
    return [.structure(.init(source: name, content: content))]
  }
}

private struct TextEchoTool: SwiftAIHub.Tool {
  let name = "textEcho"
  let description = "Returns a fixed text payload."

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> String { "hello" }

  // Emit a plain text segment explicitly; the default `makeOutputSegments`
  // path wraps `String` output as `.structure` because String conforms to
  // `ConvertibleToGeneratedContent`, which is orthogonal to what this test
  // covers (direct `.text` segment pass-through).
  func makeOutputSegments(from arguments: GeneratedContent) async throws -> [Transcript.Segment] {
    [.text(.init(content: "hello"))]
  }
}

// MARK: - Tests

@Suite("HubToolAdapter Tool.Content Mapping")
struct HubToolAdapterImageTests {

  @Test
  func imageDataPassesThroughAsImageContent() async throws {
    let adapter = try HubToolAdapter(tools: [ImageEchoTool()])
    let content = try await adapter.makeContent(name: "imageEcho", arguments: .object([:]))

    #expect(content.count == 1)
    guard case .image(let data, let mimeType, _, _) = content.first else {
      Issue.record("Expected .image content block, got \(String(describing: content.first))")
      return
    }
    #expect(mimeType == ImageEchoTool.fixtureMime)
    #expect(data == ImageEchoTool.fixtureData.base64EncodedString())
  }

  @Test
  func textPassesThroughAsTextContent() async throws {
    let adapter = try HubToolAdapter(tools: [TextEchoTool()])
    let content = try await adapter.makeContent(name: "textEcho", arguments: .object([:]))

    #expect(content.count == 1)
    guard case .text(let text, _, _) = content.first else {
      Issue.record("Expected .text content block, got \(String(describing: content.first))")
      return
    }
    #expect(text == "hello")
  }

  @Test
  func structuredOutputFallsBackToJSONText() async throws {
    let adapter = try HubToolAdapter(tools: [StructuredEchoTool()])
    let content = try await adapter.makeContent(name: "structuredEcho", arguments: .object([:]))

    #expect(content.count == 1)
    guard case .text(let text, _, _) = content.first else {
      Issue.record(
        "Expected .text fallback for structured output, got \(String(describing: content.first))")
      return
    }
    // JSON text must carry the structured payload verbatim; the SDK's
    // Tool.Content enum has no structured case on CallTool responses yet.
    #expect(text.contains("\"answer\""))
    #expect(text.contains("42"))
  }
}
