import MCP

struct CapabilitiesBuilder: Sendable {
  static func build(
    hasTools: Bool,
    hasResources: Bool,
    hasPrompts: Bool = false,
    hasCompletions: Bool = false,
    hasLogging: Bool = false
  ) -> Server.Capabilities {
    Server.Capabilities(
      completions: hasCompletions ? .init() : nil,
      logging: hasLogging ? .init() : nil,
      prompts: hasPrompts ? .init(listChanged: false) : nil,
      resources: hasResources ? .init(subscribe: false, listChanged: false) : nil,
      tools: hasTools ? .init(listChanged: false) : nil
    )
  }
}
