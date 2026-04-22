// swift-fast-mcp — FastMCPAIBridge
// Converts a SwiftAIHub.Tool into an MCP.Tool wire description.

import Foundation
import MCP
import SwiftAIHub

public enum HubToolMapper {
  public static func mapTool(_ tool: any SwiftAIHub.Tool) -> MCP.Tool {
    return MCP.Tool(
      name: tool.name,
      description: tool.description,
      inputSchema: inputSchema(for: tool)
    )
  }

  /// Minimal input schema. Real GenerationSchema → JSON Schema conversion
  /// is a follow-up; for now every hub tool advertises a free-form object.
  public static func inputSchema(for tool: any SwiftAIHub.Tool) -> Value {
    _ = tool
    return .object([
      "type": .string("object"),
      "additionalProperties": .bool(true),
    ])
  }
}
