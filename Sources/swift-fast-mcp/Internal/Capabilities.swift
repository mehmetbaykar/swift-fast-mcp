import MCP

struct CapabilitiesBuilder: Sendable {
  static func build(
    hasTools: Bool,
    hasResources: Bool,
    hasPrompts: Bool = false,
    hasCompletions: Bool = false,
    hasLogging: Bool = false,
    listChanged: Bool = false
  ) -> Server.Capabilities {
    Server.Capabilities(
      completions: hasCompletions ? .init() : nil,
      logging: hasLogging ? .init() : nil,
      prompts: hasPrompts ? .init(listChanged: listChanged) : nil,
      resources: hasResources ? .init(subscribe: false, listChanged: listChanged) : nil,
      tools: hasTools ? .init(listChanged: listChanged) : nil
    )
  }
}
