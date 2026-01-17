import Foundation
import MCP

public protocol MCPPrompt: Sendable {
  var name: String { get }
  var description: String? { get }
  var arguments: [Prompt.Argument]? { get }

  func getMessages(arguments: [String: Value]?) async throws -> [Prompt.Message]
}
