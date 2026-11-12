// swift-fast-mcp — FastMCPAIBridge tests
// String tool outputs must leave the bridge as raw text, not quoted JSON.

import FastMCPAIBridge
import Foundation
import SwiftAIHub
import Testing

import struct MCP.Tool
import enum MCP.Value

private struct MultilineStringTool: SwiftAIHub.Tool {
  let name = "multilineString"
  let description = "Returns a fixed multiline string with quotes."

  @Generable
  struct Arguments {}

  static let fixture = "line one\nline \"two\""

  func call(arguments: Arguments) async throws -> String {
    Self.fixture
  }
}

@Suite("HubToolAdapter plain string results")
struct HubToolAdapterPlainStringTests {

  @Test
  func `string structure segment is emitted as raw text not quoted JSON`() async throws {
    let adapter = try HubToolAdapter(tools: [MultilineStringTool()])
    let result = try await adapter.callTool(
      name: "multilineString",
      arguments: .object([:]),
      meta: nil
    )

    #expect(result.content.count == 1)
    guard case .text(let text, _, _) = result.content.first else {
      Issue.record("Expected one text block, got \(String(describing: result.content.first))")
      return
    }
    #expect(text == MultilineStringTool.fixture)
    #expect(text.contains("\n"))
    #expect(!text.hasPrefix("\""))
    #expect(result.structuredContent == nil)
  }
}
