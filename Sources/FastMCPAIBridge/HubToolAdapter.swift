// swift-fast-mcp — FastMCPAIBridge
// Stores hub tools by name and dispatches tools/call by MCP arguments.

import Foundation
import MCP
import SwiftAIHub

public actor HubToolAdapter {
  private var tools: [String: any SwiftAIHub.Tool] = [:]

  public init() {
    self.tools = [:]
  }

  public init(tools: [any SwiftAIHub.Tool]) throws {
    for tool in tools {
      if self.tools[tool.name] != nil {
        throw HubBridgeError.duplicateTool(name: tool.name)
      }
      self.tools[tool.name] = tool
    }
  }

  public func register(_ tool: any SwiftAIHub.Tool) throws {
    if tools[tool.name] != nil {
      throw HubBridgeError.duplicateTool(name: tool.name)
    }
    tools[tool.name] = tool
  }

  public func unregister(name: String) {
    tools.removeValue(forKey: name)
  }

  public func names() -> [String] {
    Array(tools.keys)
  }

  public func snapshot() -> [any SwiftAIHub.Tool] {
    Array(tools.values)
  }

  /// Execute a tool by name with an MCP value payload. Output is returned as
  /// GeneratedContent; callers are responsible for surfacing it back to the
  /// wire via HubValueMapper.
  public func execute(name: String, arguments: Value) async throws -> GeneratedContent {
    guard let tool = tools[name] else {
      throw HubBridgeError.toolNotFound(name)
    }

    let hubArgs = HubValueMapper.generatedContent(from: arguments)
    return try await dispatch(tool: tool, arguments: hubArgs)
  }

  private func dispatch(tool: any SwiftAIHub.Tool, arguments: GeneratedContent) async throws
    -> GeneratedContent
  {
    // Type-erased dispatch: decode Arguments via the tool's associated type,
    // invoke call, then convert Output back to GeneratedContent.
    do {
      let segments = try await tool.makeOutputSegments(from: arguments)
      return encode(segments: segments)
    } catch {
      throw HubBridgeError.invalidArguments(tool: tool.name, reason: "\(error)")
    }
  }

  private func encode(segments: [Transcript.Segment]) -> GeneratedContent {
    // Collapse transcript segments into a single GeneratedContent value.
    // Text segments → string; structure segments → their embedded content;
    // multiple segments → array.
    if segments.count == 1, let single = encodeSingle(segment: segments[0]) {
      return single
    }
    let encoded = segments.compactMap { encodeSingle(segment: $0) }
    return GeneratedContent(kind: .array(encoded))
  }

  private func encodeSingle(segment: Transcript.Segment) -> GeneratedContent? {
    switch segment {
    case .text(let text):
      return GeneratedContent(kind: .string(text.content))
    case .structure(let structure):
      return structure.content
    case .image(let image):
      switch image.source {
      case .url(let url):
        return GeneratedContent(kind: .string(url.absoluteString))
      case .data:
        return GeneratedContent(kind: .string("[image]"))
      }
    }
  }
}
