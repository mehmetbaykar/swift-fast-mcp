// swift-fast-mcp — FastMCPAIBridge
// Wires a HubToolAdapter into an MCP.Server's tools/list + tools/call handlers.

import Foundation
import MCP
import SwiftAIHub

extension Server {
  /// Register the given HubToolAdapter with this MCP Server. Installs method
  /// handlers for ListTools and CallTool that bridge SwiftAIHub tools to the
  /// MCP wire.
  @discardableResult
  public func register(hubTools adapter: HubToolAdapter) async -> Self {
    _ = self.withMethodHandler(ListTools.self) { _ in
      let tools = await adapter.listTools()
      return ListTools.Result(tools: tools)
    }

    _ = self.withMethodHandler(CallTool.self) { params in
      let args: Value = params.arguments.map { Value.object($0) } ?? .object([:])
      do {
        return try await adapter.callTool(name: params.name, arguments: args, meta: params._meta)
      } catch {
        return HubErrorMapper.mapCallToolError(error, toolName: params.name)
      }
    }

    return self
  }
}
