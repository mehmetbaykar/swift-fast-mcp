// swift-fast-mcp — FastMCPAIBridge
// Translates hub / bridge errors to MCP wire-level results.

import Foundation
import MCP

public enum HubErrorMapper {
  /// Map any Swift error surfaced during `tools/call` dispatch to an MCP result.
  /// Non-protocol errors are surfaced as `isError: true` text content so the
  /// client sees the message without the connection dropping.
  public static func mapCallToolError(_ error: Error, toolName: String) -> CallTool.Result {
    let message: String
    switch error {
    case let bridgeError as HubBridgeError:
      message = bridgeError.description
    default:
      message = "\(error)"
    }
    return CallTool.Result(
      content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
  }
}
