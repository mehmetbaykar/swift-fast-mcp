import FastMCPAIBridge
import Foundation
import Logging
import MCP

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct UpstreamMCPServerConfiguration: Sendable {
  public let name: String
  public let transport: UpstreamMCPTransport
  public let toolNamePrefix: String?

  public init(
    name: String,
    transport: UpstreamMCPTransport,
    toolNamePrefix: String? = nil
  ) {
    self.name = name
    self.transport = transport
    self.toolNamePrefix = toolNamePrefix
  }

  var effectiveToolNamePrefix: String {
    toolNamePrefix ?? "\(name)_"
  }

  func visibleToolName(for originalName: String) -> String {
    "\(effectiveToolNamePrefix)\(originalName)"
  }
}

public enum UpstreamMCPTransport: Sendable {
  case streamableHTTP(
    endpoint: URL,
    headers: [String: String] = [:],
    streaming: Bool = true
  )
}

actor UpstreamMCPManager {
  private let toolAdapter: HubToolAdapter
  private let logger: Logger
  private var connections: [String: UpstreamMCPConnection] = [:]

  init(toolAdapter: HubToolAdapter, logger: Logger) {
    self.toolAdapter = toolAdapter
    self.logger = logger
  }

  func addServer(_ configuration: UpstreamMCPServerConfiguration) async throws {
    if connections[configuration.name] != nil {
      throw FastMCPError.invalidConfiguration(
        "Upstream MCP server '\(configuration.name)' is already registered")
    }

    let connection = UpstreamMCPConnection(configuration: configuration, logger: logger)
    do {
      try await connection.connect()
      let tools = try await connection.discoverTools()
      try await toolAdapter.replaceProxiedTools(serverName: configuration.name, with: tools)
      connections[configuration.name] = connection
    } catch {
      await connection.disconnect()
      throw error
    }
  }

  func removeServer(named name: String) async -> Bool {
    let removedTools = await toolAdapter.unregisterProxiedTools(serverName: name)
    guard let connection = connections.removeValue(forKey: name) else {
      return removedTools > 0
    }
    await connection.disconnect()
    return true
  }

  func refreshServer(named name: String) async throws -> Bool {
    guard let connection = connections[name] else {
      throw FastMCPError.invalidConfiguration("Unknown upstream MCP server '\(name)'")
    }
    let tools = try await connection.discoverTools()
    let currentTools = await toolAdapter.proxiedTools(serverName: name)
    guard Self.sortedTools(currentTools.map(\.tool)) != Self.sortedTools(tools.map(\.tool)) else {
      return false
    }
    try await toolAdapter.replaceProxiedTools(serverName: name, with: tools)
    return true
  }

  func disconnectAll() async {
    let currentConnections = Array(connections.values)
    connections.removeAll()
    _ = await toolAdapter.unregisterAllProxiedTools()
    for connection in currentConnections {
      await connection.disconnect()
    }
  }

  private static func sortedTools(_ tools: [MCP.Tool]) -> [MCP.Tool] {
    tools.sorted { lhs, rhs in
      lhs.name < rhs.name
    }
  }
}

private actor UpstreamMCPConnection {
  private let configuration: UpstreamMCPServerConfiguration
  private let logger: Logger
  private var client: Client?
  private var transport: (any MCP.Transport)?

  init(configuration: UpstreamMCPServerConfiguration, logger: Logger) {
    self.configuration = configuration
    self.logger = logger
  }

  func connect() async throws {
    guard client == nil else { return }

    switch configuration.transport {
    case .streamableHTTP(let endpoint, let headers, let streaming):
      let transport = HTTPClientTransport(
        endpoint: endpoint,
        streaming: streaming,
        requestModifier: { request in
          var request = request
          for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
          }
          return request
        },
        logger: logger
      )
      let client = Client(name: "fast-mcp-\(configuration.name)-upstream", version: "1.0.0")
      _ = try await client.connect(transport: transport)
      self.transport = transport
      self.client = client
    }
  }

  func disconnect() async {
    await client?.disconnect()
    client = nil
    transport = nil
  }

  func discoverTools() async throws -> [ProxiedMCPTool] {
    let client = try requireClient()
    var allTools: [MCP.Tool] = []
    var cursor: String?

    repeat {
      let page = try await client.listTools(cursor: cursor)
      allTools.append(contentsOf: page.tools)
      cursor = page.nextCursor
    } while cursor != nil

    return allTools.map { upstreamTool in
      let originalName = upstreamTool.name
      let visibleName = configuration.visibleToolName(for: originalName)
      let visibleTool = Self.rename(upstreamTool, to: visibleName)
      return ProxiedMCPTool(
        serverName: configuration.name,
        originalName: originalName,
        tool: visibleTool,
        callHandler: { arguments, meta in
          try await self.callTool(name: originalName, arguments: arguments, meta: meta)
        }
      )
    }
  }

  private func callTool(
    name: String,
    arguments: [String: Value]?,
    meta: Metadata?
  ) async throws -> CallTool.Result {
    let client = try requireClient()
    let context: RequestContext<CallTool.Result> = try await client.callTool(
      name: name,
      arguments: arguments,
      meta: meta
    )
    return try await context.value
  }

  private func requireClient() throws -> Client {
    guard let client else {
      throw FastMCPError.invalidConfiguration(
        "Upstream MCP server '\(configuration.name)' is not connected")
    }
    return client
  }

  private static func rename(_ tool: MCP.Tool, to name: String) -> MCP.Tool {
    MCP.Tool(
      name: name,
      title: tool.title,
      description: tool.description,
      inputSchema: tool.inputSchema,
      annotations: tool.annotations,
      outputSchema: tool.outputSchema,
      icons: tool.icons,
      _meta: tool._meta
    )
  }
}
