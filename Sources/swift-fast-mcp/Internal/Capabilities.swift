import MCP

struct CapabilitiesBuilder: Sendable {
  static func build(
    hasTools: Bool,
    hasResources: Bool
  ) -> Server.Capabilities {
    Server.Capabilities(
      resources: hasResources ? .init(subscribe: false, listChanged: false) : nil,
      tools: hasTools ? .init(listChanged: false) : nil
    )
  }
}
