import FastMCP

@Generable
public enum GreetingTone: String, CaseIterable {
  case casual, formal, professional
}

@MCPPrompt("A friendly greeting conversation starter")
public struct GreetingPrompt {
  @PromptArgument("Who to greet", name: "name")
  public var who: String

  @PromptArgument("Tone to use")
  public var tone: GreetingTone = .casual

  public func getMessages() async throws -> Messages {
    switch tone {
    case .casual:
      return [
        .user("You are a friendly assistant helping \(who)."),
        .assistant("Hey \(who)! What can I help you with?"),
      ]
    case .formal:
      return [
        .user("You are a formal assistant helping \(who)."),
        .assistant("Good day, \(who). How may I assist you today?"),
      ]
    case .professional:
      return [
        .user("You are a professional assistant helping \(who)."),
        .assistant("Hello \(who), how can I help you today?"),
      ]
    }
  }
}

@MCPPrompt("Guide the assistant through a code review", name: "code_review")
public struct CodeReviewPrompt {
  @PromptArgument("Target language")
  public var language: String

  @PromptArgument("Specific focus areas")
  public var focusAreas: String?

  public func getMessages() async throws -> Messages {
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
