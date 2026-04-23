// swift-fast-mcp — FastMCPAIBridge
// Errors surfaced by the bridge during tool registration or dispatch.

import Foundation

public enum HubBridgeError: Error, CustomStringConvertible {
  case toolNotFound(String)
  case invalidArguments(tool: String, reason: String)
  case duplicateTool(name: String)

  public var description: String {
    switch self {
    case .toolNotFound(let name): return "Unknown tool: \(name)"
    case .invalidArguments(let tool, let reason): return "Invalid arguments for \(tool): \(reason)"
    case .duplicateTool(let name): return "Duplicate tool registration for name: \(name)"
    }
  }
}
