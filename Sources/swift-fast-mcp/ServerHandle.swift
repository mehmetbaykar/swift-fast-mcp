import MCP
import MCPToolkit

/// A handle to a running FastMCP server that supports dynamic tool/resource/prompt management.
///
/// When connected to a server via ``FastMCP/Builder/serverHandle(_:)``, adding or removing items
/// automatically re-registers handlers and notifies connected clients via the appropriate MCP
/// notification (`notifications/tools/list_changed`, etc.).
///
/// ## Example
///
/// ```swift
/// let handle = FastMCPServerHandle()
///
/// Task {
///   try await FastMCP.builder()
///     .name("DynamicServer")
///     .addTools([WeatherTool()])
///     .serverHandle(handle)
///     .run()
/// }
///
/// // Later, from another task:
/// await handle.addTool(MathTool())
/// await handle.removeTool(named: "get_weather")
/// ```
public actor FastMCPServerHandle {
  private var tools: [any MCPTool]
  private var resources: [any MCPResource]
  private var prompts: [any MCPPrompt]
  private var servers: [Server] = []

  private let toolDeduplicator = ToolDeduplicator()
  private let resourceDeduplicator = ResourceDeduplicator()
  private let promptDeduplicator = PromptDeduplicator()

  public init() {
    self.tools = []
    self.resources = []
    self.prompts = []
  }

  /// Called by `FastMCP.Builder.run()` to seed the handle with initial state.
  func configure(
    tools: [any MCPTool],
    resources: [any MCPResource],
    prompts: [any MCPPrompt]
  ) {
    self.tools = tools
    self.resources = resources
    self.prompts = prompts
  }

  /// Called when a new `Server` instance is created (once for stdio, per-session for HTTP).
  func registerServer(_ server: Server) {
    servers.append(server)
  }

  // MARK: - Tools

  /// Add a single tool at runtime. Re-registers handlers and notifies clients.
  public func addTool(_ tool: any MCPTool) async {
    tools = toolDeduplicator.deduplicate(tools, adding: [tool])
    await reregisterTools()
    await notifyToolsChanged()
  }

  /// Add multiple tools at runtime. Re-registers handlers and notifies clients.
  public func addTools(_ newTools: [any MCPTool]) async {
    tools = toolDeduplicator.deduplicate(tools, adding: newTools)
    await reregisterTools()
    await notifyToolsChanged()
  }

  /// Remove a tool by name. Re-registers handlers and notifies clients if the tool existed.
  public func removeTool(named name: String) async {
    let before = tools.count
    tools.removeAll { $0.name == name }
    if tools.count != before {
      await reregisterTools()
      await notifyToolsChanged()
    }
  }

  /// The current list of registered tools.
  public var currentTools: [any MCPTool] { tools }

  // MARK: - Resources

  /// Add a single resource at runtime. Re-registers handlers and notifies clients.
  public func addResource(_ resource: any MCPResource) async {
    resources = resourceDeduplicator.deduplicate(resources, adding: [resource])
    await reregisterResources()
    await notifyResourcesChanged()
  }

  /// Add multiple resources at runtime. Re-registers handlers and notifies clients.
  public func addResources(_ newResources: [any MCPResource]) async {
    resources = resourceDeduplicator.deduplicate(resources, adding: newResources)
    await reregisterResources()
    await notifyResourcesChanged()
  }

  /// Remove a resource by URI. Re-registers handlers and notifies clients if the resource existed.
  public func removeResource(uri: String) async {
    let before = resources.count
    resources.removeAll { $0.uri == uri }
    if resources.count != before {
      await reregisterResources()
      await notifyResourcesChanged()
    }
  }

  /// The current list of registered resources.
  public var currentResources: [any MCPResource] { resources }

  // MARK: - Prompts

  /// Add a single prompt at runtime. Re-registers handlers and notifies clients.
  public func addPrompt(_ prompt: any MCPPrompt) async {
    prompts = promptDeduplicator.deduplicate(prompts, adding: [prompt])
    await reregisterPrompts()
    await notifyPromptsChanged()
  }

  /// Add multiple prompts at runtime. Re-registers handlers and notifies clients.
  public func addPrompts(_ newPrompts: [any MCPPrompt]) async {
    prompts = promptDeduplicator.deduplicate(prompts, adding: newPrompts)
    await reregisterPrompts()
    await notifyPromptsChanged()
  }

  /// Remove a prompt by name. Re-registers handlers and notifies clients if the prompt existed.
  public func removePrompt(named name: String) async {
    let before = prompts.count
    prompts.removeAll { $0.name == name }
    if prompts.count != before {
      await reregisterPrompts()
      await notifyPromptsChanged()
    }
  }

  /// The current list of registered prompts.
  public var currentPrompts: [any MCPPrompt] { prompts }

  // MARK: - Private

  private func reregisterTools() async {
    for server in servers {
      await server.register(tools: tools)
    }
  }

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
