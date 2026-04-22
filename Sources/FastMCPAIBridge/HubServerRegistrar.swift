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
      let tools = await adapter.snapshot()
      return ListTools.Result(tools: tools.map { HubToolMapper.mapTool($0) })
    }

    _ = self.withMethodHandler(CallTool.self) { params in
      let args: Value = params.arguments.map { Value.object($0) } ?? .object([:])
      do {
        let output = try await adapter.execute(name: params.name, arguments: args)
        let content: MCP.Tool.Content
        switch output.kind {
        case .string(let s):
          content = .text(text: s, annotations: nil, _meta: nil)
        default:
          content = .text(text: output.jsonString, annotations: nil, _meta: nil)
        }
        return CallTool.Result(content: [content], isError: false)
      } catch {
        return HubErrorMapper.mapCallToolError(error, toolName: params.name)
      }
    }

    return self
  }
}
