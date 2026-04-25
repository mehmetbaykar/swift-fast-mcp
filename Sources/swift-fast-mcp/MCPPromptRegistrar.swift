import Foundation
import MCP

extension PromptMessage {
  internal func toPromptMessage() -> MCP.Prompt.Message {
    switch role {
    case .user:
      return .user(content.toPromptContent())
    case .assistant:
      return .assistant(content.toPromptContent())
    }
  }
}

extension PromptMessageContent {
  internal func toPromptContent() -> MCP.Prompt.Message.Content {
    switch self {
    case .text(let text):
      return .text(text: text)
    case .image(let data, let mimeType):
      return .image(data: data, mimeType: mimeType)
    case .audio(let data, let mimeType):
      return .audio(data: data, mimeType: mimeType)
    case .resource(let uri, let mimeType, let text, let blob):
      if let blob {
        let data = Data(base64Encoded: blob) ?? Data()
        return .resource(resource: .binary(data, uri: uri, mimeType: mimeType))
      } else {
        return .resource(resource: .text(text ?? "", uri: uri, mimeType: mimeType))
      }
    }
  }
}

extension MCPPrompt {
  public func toPrompt() -> MCP.Prompt {
    let promptArguments = arguments.map {
      MCP.Prompt.Argument(
        name: $0.name,
        description: $0.description,
        required: $0.required ? true : nil
      )
    }
    return MCP.Prompt(
      name: name,
      description: description,
      arguments: promptArguments.isEmpty ? nil : promptArguments
    )
  }
}

extension Server {
  public func register(prompts: [any MCPPrompt]) async {
    self.withMethodHandler(ListPrompts.self) { _ in
      .init(prompts: prompts.map { $0.toPrompt() }, nextCursor: nil)
    }

    self.withMethodHandler(GetPrompt.self) { params async throws in
      guard let prompt = prompts.first(where: { $0.name == params.name }) else {
        throw MCPError.invalidParams("Unknown prompt: \(params.name)")
      }
      let messages = try await prompt.getMessages(arguments: params.arguments ?? [:])
      return GetPrompt.Result(
        description: prompt.description,
        messages: messages.map { $0.toPromptMessage() }
      )
    }
  }
}
