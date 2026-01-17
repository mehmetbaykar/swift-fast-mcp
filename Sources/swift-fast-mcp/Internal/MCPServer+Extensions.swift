import MCP

extension Server {
  public func register(prompts: [any MCPPrompt]) async {
    guard !prompts.isEmpty else { return }

    self.withMethodHandler(ListPrompts.self) { _ in
      let mcpPrompts = prompts.map { prompt in
        Prompt(
          name: prompt.name,
          description: prompt.description,
          arguments: prompt.arguments
        )
      }
      return .init(prompts: mcpPrompts, nextCursor: nil)
    }

    self.withMethodHandler(GetPrompt.self) { params in
      guard let prompt = prompts.first(where: { $0.name == params.name }) else {
        throw MCPError.invalidParams("Unknown prompt: \(params.name)")
      }
      let messages = try await prompt.getMessages(arguments: params.arguments)
      return .init(description: prompt.description, messages: messages)
    }
  }
}
