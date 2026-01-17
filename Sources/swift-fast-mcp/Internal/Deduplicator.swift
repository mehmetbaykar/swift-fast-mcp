import MCPToolkit

struct ToolDeduplicator: Sendable {
  func deduplicate(_ existing: [any MCPTool], adding new: [any MCPTool]) -> [any MCPTool] {
    var result = existing
    let existingNames = Set(existing.map { $0.name })

    for tool in new where !existingNames.contains(tool.name) {
      result.append(tool)
    }

    return result
  }
}

struct ResourceDeduplicator: Sendable {
  func deduplicate(_ existing: [any MCPResource], adding new: [any MCPResource])
    -> [any MCPResource]
  {
    var result = existing
    let existingURIs = Set(existing.map { $0.uri })

    for resource in new where !existingURIs.contains(resource.uri) {
      result.append(resource)
    }

    return result
  }
}

struct PromptDeduplicator: Sendable {
  func deduplicate(_ existing: [any MCPPrompt], adding new: [any MCPPrompt])
    -> [any MCPPrompt]
  {
    var result = existing
    let existingNames = Set(existing.map { $0.name })

    for prompt in new where !existingNames.contains(prompt.name) {
      result.append(prompt)
    }

    return result
  }
}
