import MCP

struct CapabilitiesBuilder: Sendable {
  static func build(
    hasTools: Bool,
    hasResources: Bool,
    hasPrompts: Bool = false,
    hasSampling: Bool = false
  ) -> Server.Capabilities {
    Server.Capabilities(
      prompts: hasPrompts ? .init(listChanged: false) : nil,
      resources: hasResources ? .init(subscribe: false, listChanged: false) : nil,
      sampling: hasSampling ? .init() : nil,
      tools: hasTools ? .init(listChanged: false) : nil
    )
  }
}
