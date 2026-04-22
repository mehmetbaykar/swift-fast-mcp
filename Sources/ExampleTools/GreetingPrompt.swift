import FastMCP

public struct GreetingPrompt: MCPPrompt {
  public let name = "greeting"
  public let description: String? = "A friendly greeting conversation starter"
  public let arguments: [PromptArgumentSpec] = [
    PromptArgumentSpec(name: "name", description: "Who to greet", required: true),
    PromptArgumentSpec(name: "formal", description: "Use formal tone", required: false),
  ]

  public init() {}

  public func getMessages(arguments: [String: String]) async throws -> Messages {
    let who = arguments["name"] ?? ""
    let formal = (arguments["formal"] ?? "").lowercased() == "true"
    if formal {
      return [
        .user("You are a formal assistant helping \(who)."),
        .assistant("Good day, \(who). How may I assist you today?"),
      ]
    } else {
      return [
        .user("You are a friendly assistant helping \(who)."),
        .assistant("Hey \(who)! What can I help you with?"),
      ]
    }
  }
}

public struct CodeReviewPrompt: MCPPrompt {
  public let name = "code_review"
  public let description: String? = "Guide the assistant through a code review"
  public let arguments: [PromptArgumentSpec] = [
    PromptArgumentSpec(name: "language", description: "Target language", required: true),
    PromptArgumentSpec(name: "focusAreas", description: "Specific focus areas", required: false),
  ]

  public init() {}

  public func getMessages(arguments: [String: String]) async throws -> Messages {
    let language = arguments["language"] ?? ""
    let focusAreas = arguments["focusAreas"]
    var messages: Messages = [
      .user("You are an expert \(language) code reviewer."),
      .user("Please review the code I'm about to share. Focus on:"),
      PromptMessage(
        role: .user,
        content: .text(
          """
          1. Code correctness and potential bugs
          2. Performance implications
          3. Security vulnerabilities
          4. Code style and best practices
          """
        )
      ),
    ]
    let suffix = focusAreas.map { ", with focus on \($0)" } ?? ""
    messages.append(
      .assistant(
        "I understand. Please share the \(language) code you'd like me to review\(suffix)."
      )
    )
    return messages
  }
}
