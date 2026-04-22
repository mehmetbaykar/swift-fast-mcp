import FastMCPAIBridge
import MCP
import SwiftAIHub

/// A handle to a running FastMCP server that supports dynamic tool/resource/prompt management.
///
/// When connected to a server via ``FastMCP/Builder/serverHandle(_:)``, adding or removing items
/// re-registers handlers and notifies connected clients via the appropriate MCP notification.
public actor FastMCPServerHandle {
  private var toolAdapter: HubToolAdapter
  private var resources: [any MCPResource]
  private var prompts: [any MCPPrompt]
  private var servers: [Server] = []

  private let resourceDeduplicator = ResourceDeduplicator()
  private let promptDeduplicator = PromptDeduplicator()

  public init() {
    self.toolAdapter = HubToolAdapter()
    self.resources = []
    self.prompts = []
  }

  func configure(
    toolAdapter: HubToolAdapter,
    resources: [any MCPResource],
    prompts: [any MCPPrompt]
  ) {
    self.toolAdapter = toolAdapter
    self.resources = resources
    self.prompts = prompts
  }

  func registerServer(_ server: Server) {
    servers.append(server)
  }

  // MARK: - Tools

  public func addTool(_ tool: any SwiftAIHub.Tool) async {
    await toolAdapter.register(tool)
    await notifyToolsChanged()
  }

  public func addTools(_ newTools: [any SwiftAIHub.Tool]) async {
    for tool in newTools {
      await toolAdapter.register(tool)
    }
    await notifyToolsChanged()
  }

  public func removeTool(named name: String) async {
    let before = await toolAdapter.names().count
    await toolAdapter.unregister(name: name)
    let after = await toolAdapter.names().count
    if before != after {
      await notifyToolsChanged()
    }
  }

  public var currentToolAdapter: HubToolAdapter { toolAdapter }

  // MARK: - Resources

  public func addResource(_ resource: any MCPResource) async {
    resources = resourceDeduplicator.deduplicate(resources, adding: [resource])
    await reregisterResources()
    await notifyResourcesChanged()
  }

  public func addResources(_ newResources: [any MCPResource]) async {
    resources = resourceDeduplicator.deduplicate(resources, adding: newResources)
    await reregisterResources()
    await notifyResourcesChanged()
  }

  public func removeResource(uri: String) async {
    let before = resources.count
    resources.removeAll { $0.uri == uri }
    if resources.count != before {
      await reregisterResources()
      await notifyResourcesChanged()
    }
  }

  public var currentResources: [any MCPResource] { resources }

  // MARK: - Prompts

  public func addPrompt(_ prompt: any MCPPrompt) async {
    prompts = promptDeduplicator.deduplicate(prompts, adding: [prompt])
    await reregisterPrompts()
    await notifyPromptsChanged()
  }

  public func addPrompts(_ newPrompts: [any MCPPrompt]) async {
    prompts = promptDeduplicator.deduplicate(prompts, adding: newPrompts)
    await reregisterPrompts()
    await notifyPromptsChanged()
  }

  public func removePrompt(named name: String) async {
    let before = prompts.count
    prompts.removeAll { $0.name == name }
    if prompts.count != before {
      await reregisterPrompts()
      await notifyPromptsChanged()
    }
  }

  public var currentPrompts: [any MCPPrompt] { prompts }

  // MARK: - Private

  private func reregisterResources() async {
    for server in servers {
      await server.register(resources: resources)
    }
  }

  private func reregisterPrompts() async {
    for server in servers {
      await server.register(prompts: prompts)
    }
  }

  private func notifyToolsChanged() async {
    var deadIndices: [Int] = []
    for (index, server) in servers.enumerated() {
      do {
        try await server.notify(ToolListChangedNotification.message())
      } catch {
        deadIndices.append(index)
      }
    }
    removeServers(at: deadIndices)
  }

  private func notifyResourcesChanged() async {
    var deadIndices: [Int] = []
    for (index, server) in servers.enumerated() {
      do {
        try await server.notify(ResourceListChangedNotification.message())
      } catch {
        deadIndices.append(index)
      }
    }
    removeServers(at: deadIndices)
  }

  private func notifyPromptsChanged() async {
    var deadIndices: [Int] = []
    for (index, server) in servers.enumerated() {
      do {
        try await server.notify(PromptListChangedNotification.message())
      } catch {
        deadIndices.append(index)
      }
    }
    removeServers(at: deadIndices)
  }

  private func removeServers(at indices: [Int]) {
    for index in indices.reversed() {
      servers.remove(at: index)
    }
  }
}
