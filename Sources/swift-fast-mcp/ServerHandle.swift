import FastMCPAIBridge
import MCP
import SwiftAIHub
import SwiftAIHubMCP

/// A handle to a running FastMCP server that supports dynamic tool/resource/prompt management.
///
/// When connected to a server via ``FastMCP/Builder/serverHandle(_:)``, adding or removing items
/// re-registers handlers and notifies connected clients via the appropriate MCP notification.
public actor FastMCPServerHandle {
  private var toolAdapter: HubToolAdapter
  private var upstreamManager: UpstreamMCPManager?
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
    upstreamManager: UpstreamMCPManager?,
    resources: [any MCPResource],
    prompts: [any MCPPrompt]
  ) {
    self.toolAdapter = toolAdapter
    self.upstreamManager = upstreamManager
    self.resources = resources
    self.prompts = prompts
  }

  func registerServer(_ server: Server) {
    servers.append(server)
  }

  /// Register tool/resource/prompt handlers on a new HTTP session's `Server`
  /// from the current catalog. Must be called BEFORE `server.start(...)`.
  ///
  /// Paired with ``activateHTTPSession(_:)``, which publishes the server to
  /// the handle's tracking list after `start` has completed. Splitting the
  /// registration and activation avoids a race where notifying an
  /// un-started server throws a connection-not-initialized error and the
  /// existing prune logic removes it from the tracking list before it has
  /// begun servicing requests.
  func registerHTTPSession(_ server: Server) async {
    await server.register(hubTools: toolAdapter)
    await server.register(resources: resources)
    await server.register(prompts: prompts)
  }

  /// Publish a started HTTP session's `Server` to the handle's tracking list
  /// so subsequent catalog mutations reach it, then refresh resource and
  /// prompt registrations against the current state in case the catalog
  /// changed while the server was starting.
  func activateHTTPSession(_ server: Server) async {
    servers.append(server)
    await server.register(resources: resources)
    await server.register(prompts: prompts)
  }

  // MARK: - Tools

  public func addTool(_ tool: any SwiftAIHub.Tool) async throws {
    try await toolAdapter.register(tool)
    await notifyToolsChanged()
  }

  public func addTools(_ newTools: [any SwiftAIHub.Tool]) async throws {
    // Prevalidate against existing names AND duplicates within the batch
    // before any adapter mutation. Previously this loop registered each
    // tool in sequence and, on a mid-batch throw, left earlier items
    // committed without a ToolListChangedNotification — leaving clients
    // with a stale view of the catalog.
    var seen = Set(await toolAdapter.names())
    for tool in newTools {
      if !seen.insert(tool.name).inserted {
        throw HubBridgeError.duplicateTool(name: tool.name)
      }
    }
    for tool in newTools {
      try await toolAdapter.register(tool)
    }
    await notifyToolsChanged()
  }

  public func addTools(_ source: any SwiftAIHub.ToolSource) async throws {
    try await addTools(source.resolveTools())
  }

  public func addMCPToolProvider(_ provider: any MCPToolProviderProtocol) async throws {
    try await addTools(provider)
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

  // MARK: - Upstream MCP Servers

  public func addUpstreamMCPServer(_ configuration: UpstreamMCPServerConfiguration) async throws {
    guard let upstreamManager else {
      throw FastMCPError.invalidConfiguration(
        "FastMCPServerHandle is not attached to a running server")
    }
    try await upstreamManager.addServer(configuration)
    await notifyToolsChanged()
  }

  public func removeUpstreamMCPServer(named name: String) async throws {
    guard let upstreamManager else {
      throw FastMCPError.invalidConfiguration(
        "FastMCPServerHandle is not attached to a running server")
    }
    let changed = await upstreamManager.removeServer(named: name)
    if changed {
      await notifyToolsChanged()
    }
  }

  public func refreshUpstreamMCPServer(named name: String) async throws {
    guard let upstreamManager else {
      throw FastMCPError.invalidConfiguration(
        "FastMCPServerHandle is not attached to a running server")
    }
    let changed = try await upstreamManager.refreshServer(named: name)
    if changed {
      await notifyToolsChanged()
    }
  }

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
