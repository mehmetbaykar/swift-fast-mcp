// A strongly typed interface for exposing prompt templates in a Model Context Protocol server.
//
// Conforming types describe their arguments with a list of `PromptArgumentSpec` values and
// return messages keyed off a raw `[String: String]` payload (matching the MCP wire format).

/// Declarative description of a prompt argument surfaced through `prompts/list`.
public struct PromptArgumentSpec: Sendable {
  public let name: String
  public let description: String?
  public let required: Bool

  public init(name: String, description: String? = nil, required: Bool = false) {
    self.name = name
    self.description = description
    self.required = required
  }
}

public protocol MCPPrompt: Sendable {
  typealias Messages = [PromptMessage]

  var name: String { get }
  var description: String? { get }
  var arguments: [PromptArgumentSpec] { get }

  func getMessages(arguments: [String: String]) async throws -> Messages
}

extension MCPPrompt {
  public var description: String? { nil }
  public var arguments: [PromptArgumentSpec] { [] }
}

// MARK: - Prompt Error

public struct PromptError: Error, Sendable {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }
}

// MARK: - Prompt Message

public struct PromptMessage: Sendable {
  public let role: PromptMessageRole
  public let content: PromptMessageContent

  public init(role: PromptMessageRole, content: PromptMessageContent) {
    self.role = role
    self.content = content
  }

  public static func user(_ text: String) -> PromptMessage {
    PromptMessage(role: .user, content: .text(text))
  }

  public static func assistant(_ text: String) -> PromptMessage {
    PromptMessage(role: .assistant, content: .text(text))
  }

  public static func user(imageData data: String, mimeType: String) -> PromptMessage {
    PromptMessage(role: .user, content: .image(data: data, mimeType: mimeType))
  }

  public static func assistant(imageData data: String, mimeType: String) -> PromptMessage {
    PromptMessage(role: .assistant, content: .image(data: data, mimeType: mimeType))
  }

  public static func user(audioData data: String, mimeType: String) -> PromptMessage {
    PromptMessage(role: .user, content: .audio(data: data, mimeType: mimeType))
  }

  public static func assistant(audioData data: String, mimeType: String) -> PromptMessage {
    PromptMessage(role: .assistant, content: .audio(data: data, mimeType: mimeType))
  }

  public static func user(
    resource uri: String,
    mimeType: String,
    text: String? = nil,
    blob: String? = nil
  ) -> PromptMessage {
    PromptMessage(
      role: .user,
      content: .resource(uri: uri, mimeType: mimeType, text: text, blob: blob)
    )
  }

  public static func assistant(
    resource uri: String,
    mimeType: String,
    text: String? = nil,
    blob: String? = nil
  ) -> PromptMessage {
    PromptMessage(
      role: .assistant,
      content: .resource(uri: uri, mimeType: mimeType, text: text, blob: blob)
    )
  }
}

extension PromptMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
  public init(stringLiteral value: String) {
    self.role = .user
    self.content = .text(value)
  }
}

public enum PromptMessageRole: String, Sendable, Hashable, Codable {
  case user
  case assistant
}

public enum PromptMessageContent: Sendable, Hashable {
  case text(String)
  case image(data: String, mimeType: String)
  case audio(data: String, mimeType: String)
  case resource(uri: String, mimeType: String, text: String?, blob: String?)
}

public typealias PromptMessageBuilder = ContentBuilder<PromptMessage>

extension ContentBuilder where Item == PromptMessage {
  public static func buildExpression(_ group: PromptMessageGroup) -> PromptMessage {
    group.asMessage()
  }
}

public struct PromptMessageGroup: Sendable {
  private let role: PromptMessageRole
  private let lines: [String]
  private let separator: String

  public init(
    role: PromptMessageRole,
    separator: String = "\n",
    @ArrayBuilder<String> _ content: () -> [String]
  ) {
    self.role = role
    self.lines = content()
    self.separator = separator
  }

  fileprivate func asMessage() -> PromptMessage {
    PromptMessage(role: role, content: .text(lines.joined(separator: separator)))
  }
}
