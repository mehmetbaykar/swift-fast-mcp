import FastMCP
import MCP

public struct GreetingPrompt: MCPPrompt {
  public let name = "greeting"
  public let description: String? = "A friendly greeting conversation starter"
  public let arguments: [Prompt.Argument]? = [
    .init(name: "name", description: "Name of the person to greet", required: true),
    .init(name: "formal", description: "Use formal greeting style"),
  ]

  public init() {}

  public func getMessages(arguments: [String: Value]?) async throws -> [Prompt.Message] {
    let name = arguments?["name"]?.stringValue ?? "friend"
    let formal = arguments?["formal"]?.boolValue ?? false

    if formal {
      return [
        .user("You are a formal assistant helping \(name)."),
        .assistant("Good day, \(name). How may I assist you today?"),
      ]
    } else {
      return [
        .user("You are a friendly assistant helping \(name)."),
        .assistant("Hey \(name)! What can I help you with?"),
      ]
    }
  }
}
