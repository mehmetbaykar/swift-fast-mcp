import FastMCP

/// A friendly greeting conversation starter prompt.
///
/// This example demonstrates the strongly-typed MCPPrompt pattern with `@Schemable` arguments.
///
/// ## Usage
///
/// ```swift
/// let server = FastMCP.builder()
///   .addPrompts([GreetingPrompt()])
///   .run()
/// ```
public struct GreetingPrompt: MCPPrompt {
  public let name = "greeting"
  public let description: String? = "A friendly greeting conversation starter"

  /// The arguments for the greeting prompt.
  @Schemable
  public struct Arguments {
    /// Name of the person to greet
    public let name: String
    /// Use formal greeting style (optional, defaults to casual)
    public let formal: Bool?

    public init(name: String, formal: Bool? = nil) {
      self.name = name
      self.formal = formal
    }
  }

  public init() {}

  /// Generates greeting messages based on the provided arguments.
  ///
  /// - Parameter arguments: The strongly-typed arguments for this prompt.
  /// - Returns: An array of prompt messages forming a conversation starter.
  public func getMessages(arguments: Arguments) async throws -> Messages {
    if arguments.formal == true {
      return [
        .user("You are a formal assistant helping \(arguments.name)."),
        .assistant("Good day, \(arguments.name). How may I assist you today?"),
      ]
    } else {
      return [
        .user("You are a friendly assistant helping \(arguments.name)."),
        .assistant("Hey \(arguments.name)! What can I help you with?"),
      ]
    }
  }
}

/// A code review prompt that demonstrates multi-message prompts.
///
/// This example shows how to create prompts with multiple messages for guiding
/// an AI assistant through a specific workflow.
public struct CodeReviewPrompt: MCPPrompt {
  public let name = "code_review"
  public let description: String? = "Guide the assistant through a code review"

  @Schemable
  public struct Arguments {
    /// The programming language of the code
    public let language: String
    /// Focus areas for the review (optional)
    public let focusAreas: String?

    public init(language: String, focusAreas: String? = nil) {
      self.language = language
      self.focusAreas = focusAreas
    }
  }

  public init() {}

  @PromptMessageBuilder
  public func getMessages(arguments: Arguments) async throws -> Messages {
    PromptMessage.user(
      "You are an expert \(arguments.language) code reviewer."
    )
    PromptMessage.user(
      "Please review the code I'm about to share. Focus on:"
    )
    PromptMessageGroup(role: .user) {
      "1. Code correctness and potential bugs"
      "2. Performance implications"
      "3. Security vulnerabilities"
      "4. Code style and best practices"
    }

    PromptMessage.assistant(
      "I understand. Please share the \(arguments.language) code you'd like me to review\(arguments.focusAreas.map { ", with focus on \($0)" } ?? "")."
    )
  }
}
