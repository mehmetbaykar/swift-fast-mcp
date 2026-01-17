import Foundation
import Logging
import MCP
import MCPToolkit
import ServiceLifecycle
import UnixSignals

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public enum FastMCP {
  public static func builder() -> Builder {
    Builder()
  }
}

extension FastMCP {
  public struct Builder: Sendable {
    var serverName: String
    var serverVersion: String
    var tools: [any MCPTool]
    var resources: [any MCPResource]
    var transportConfig: Transport
    var logLevel: Logger.Level
    var shutdownSignals: [UnixSignal]
    var onStartHandler: (@Sendable () async -> Void)?
    var onShutdownHandler: (@Sendable () async -> Void)?

    let toolDeduplicator = ToolDeduplicator()
    let resourceDeduplicator = ResourceDeduplicator()

    public init() {
      self.serverName = ProcessInfo.processInfo.processName
      self.serverVersion = "1.0.0"
      self.tools = []
      self.resources = []
      self.transportConfig = .stdio
      self.logLevel = .info
      self.shutdownSignals = [.sigterm, .sigint]
      self.onStartHandler = nil
      self.onShutdownHandler = nil
    }

    public func name(_ name: String) -> Builder {
      var copy = self
      copy.serverName = name
      return copy
    }

    public func version(_ version: String) -> Builder {
      var copy = self
      copy.serverVersion = version
      return copy
    }

    public func addTools(_ newTools: [any MCPTool]) -> Builder {
      var copy = self
      copy.tools = toolDeduplicator.deduplicate(copy.tools, adding: newTools)
      return copy
    }

    public func addResources(_ newResources: [any MCPResource]) -> Builder {
      var copy = self
      copy.resources = resourceDeduplicator.deduplicate(copy.resources, adding: newResources)
      return copy
    }

    public func transport(_ transport: Transport) -> Builder {
      var copy = self
      copy.transportConfig = transport
      return copy
    }

    public func logLevel(_ level: Logger.Level) -> Builder {
      var copy = self
      copy.logLevel = level
      return copy
    }

    public func shutdownSignals(_ signals: [UnixSignal]) -> Builder {
      var copy = self
      copy.shutdownSignals = signals
      return copy
    }

    public func onStart(_ handler: @escaping @Sendable () async -> Void) -> Builder {
      var copy = self
      copy.onStartHandler = handler
      return copy
    }

    public func onShutdown(_ handler: @escaping @Sendable () async -> Void) -> Builder {
      var copy = self
      copy.onShutdownHandler = handler
      return copy
    }

    public func run() async throws {
      try validate()

      var logger = Logger(label: serverName)
      logger.logLevel = logLevel

      if tools.isEmpty && resources.isEmpty {
        logger.warning("Server starting with no tools or resources registered")
      }

      let capabilities = CapabilitiesBuilder.build(
        hasTools: !tools.isEmpty,
        hasResources: !resources.isEmpty
      )

      let server = Server(
        name: serverName,
        version: serverVersion,
        capabilities: capabilities
      )

      await server.register(tools: tools)
      await server.register(resources: resources)

      let mcpTransport = StdioTransport()

      let service = FastMCPService(
        server: server,
        transport: mcpTransport,
        logger: logger,
        onStart: onStartHandler,
        onShutdown: onShutdownHandler
      )

      let serviceGroup = ServiceGroup(
        services: [service],
        gracefulShutdownSignals: shutdownSignals,
        logger: logger
      )

      try await serviceGroup.run()
    }

    func validate() throws {
      if case .http = transportConfig {
        throw FastMCPError.invalidConfiguration(
          "HTTP transport is not yet implemented - use .transport(.stdio) for v1")
      }
    }
  }
}
