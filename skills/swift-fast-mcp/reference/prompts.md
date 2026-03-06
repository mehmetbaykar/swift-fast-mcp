# MCPPrompt Reference

## Protocol

```swift
public protocol MCPPrompt: Sendable {
  associatedtype Arguments: Decodable & Sendable
  var name: String { get }
  var description: String? { get }
  func getMessages(arguments: Arguments) async throws -> Messages
}
```

- `Messages` is a typealias for `[PromptMessage]`
- Messages are created with `.user("...")` and `.assistant("...")`

## Simple Prompt

```swift
import FastMCP

public struct GreetingPrompt: MCPPrompt {
  public let name = "greeting"
  public let description: String? = "A friendly greeting conversation starter"

  public init() {}

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
```

## Advanced Prompt with @PromptMessageBuilder

Use the `@PromptMessageBuilder` result builder for more complex multi-message prompts:

```swift
import FastMCP

public struct CodeReviewPrompt: MCPPrompt {
  public let name = "code_review"
  public let description: String? = "Guide the assistant through a code review"

  public init() {}

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
```

### @PromptMessageBuilder Features

- Annotate `getMessages` with `@PromptMessageBuilder` instead of returning an array
- Use `PromptMessage.user(...)` and `PromptMessage.assistant(...)` as builder statements
- `PromptMessageGroup(role:)` groups multiple string literals into messages with the same role
- Doc comments on Arguments properties become schema descriptions

## Registration

```swift
try await FastMCP.builder()
  .addPrompts([
    GreetingPrompt(),
    CodeReviewPrompt(),
  ])
  .run()
```

Multiple `.addPrompts()` calls accumulate prompts. Duplicates (same `name`) are silently dropped — first registration wins.

## Key Requirements

- Arguments struct must be annotated with `@Schemable`
- Arguments struct needs `public init()` for cross-module access
- Prompt struct needs `public init() {}`
- `name` and `description` are `let` properties
- `description` type is `String?`
- Doc comments on Arguments properties become JSON Schema descriptions
- Return type is `Messages` (typealias for `[PromptMessage]`)
