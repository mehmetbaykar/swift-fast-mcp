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
  ///
  /// - Note: This path collapses image segments to a sentinel string and
  ///   stringifies structured output. Prefer ``makeContent(name:arguments:)``
  ///   when bridging directly to MCP `Tool.Content`, which preserves typed
  ///   image blocks and only falls back to JSON text for structured output
  ///   (the MCP SDK does not yet expose structured content on CallTool).
  public func execute(name: String, arguments: Value) async throws -> GeneratedContent {
    guard let tool = tools[name] else {
      throw HubBridgeError.toolNotFound(name)
    }

    let hubArgs = HubValueMapper.generatedContent(from: arguments)
    return try await dispatch(tool: tool, arguments: hubArgs)
  }

  /// Execute a tool by name and return MCP-typed content blocks.
  ///
  /// Segments map through to MCP `Tool.Content` without the lossy
  /// `GeneratedContent` detour:
  /// - `.text` → `.text`
  /// - `.image(.data)` → `.image(data: base64, mimeType:)`
  /// - `.image(.url)` → `.resourceLink(uri:)` (MCP image content requires
  ///   inline data + mimeType; URL-only images are surfaced as a link)
  /// - `.structure` → `.text(jsonString)` — the current MCP SDK's
  ///   `Tool.Content` enum is sealed and does not expose a structured
  ///   content case on CallTool responses; we serialize as JSON text.
  ///   TODO: switch to a structured content case once the MCP SDK adds one.
  public func makeContent(name: String, arguments: Value) async throws -> [MCP.Tool.Content] {
    guard let tool = tools[name] else {
      throw HubBridgeError.toolNotFound(name)
    }

    let hubArgs = HubValueMapper.generatedContent(from: arguments)
    let segments: [Transcript.Segment]
    do {
      segments = try await tool.makeOutputSegments(from: hubArgs)
    } catch {
      throw HubBridgeError.invalidArguments(tool: tool.name, reason: "\(error)")
    }
    return segments.map(Self.toolContent(from:))
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

  /// Map a single hub transcript segment onto an MCP content block, preserving
  /// typed image payloads and falling back to JSON text for structured output
  /// (see ``makeContent(name:arguments:)`` for the SDK constraint).
  static func toolContent(from segment: Transcript.Segment) -> MCP.Tool.Content {
    switch segment {
    case .text(let text):
      return .text(text: text.content, annotations: nil, _meta: nil)
    case .image(let image):
      switch image.source {
      case .data(let data, let mimeType):
        return .image(
          data: data.base64EncodedString(),
          mimeType: mimeType,
          annotations: nil,
          _meta: nil
        )
      case .url(let url):
        return .resourceLink(uri: url.absoluteString, name: url.lastPathComponent)
      }
    case .structure(let structure):
      // MCP SDK's Tool.Content has no structured-content case on CallTool
      // responses yet; serialize to JSON text so the client still receives
      // the full payload instead of a sentinel.
      return .text(text: structure.content.jsonString, annotations: nil, _meta: nil)
    }
  }
}
