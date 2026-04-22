/// Public macro declarations that expand via the `FastMCPMacros` compiler plugin.

@attached(
  member,
  names: named(name), named(description), named(arguments), named(init), named(getMessages)
)
@attached(extension, conformances: MCPPrompt, Sendable)
public macro MCPPrompt(_ description: String, name: String? = nil) =
  #externalMacro(module: "FastMCPMacros", type: "MCPPromptMacro")

@attached(peer)
public macro PromptArgument(
  _ description: String,
  name: String? = nil,
  required: Bool? = nil
) = #externalMacro(module: "FastMCPMacros", type: "PromptArgumentMacro")

@attached(
  member,
  names: named(uri), named(name), named(description), named(mimeType), named(init)
)
@attached(extension, conformances: MCPResource, Sendable)
public macro MCPResource(
  _ uri: String,
  name: String? = nil,
  description: String? = nil,
  mimeType: MCPResourceMimeType? = nil
) = #externalMacro(module: "FastMCPMacros", type: "MCPResourceMacro")
