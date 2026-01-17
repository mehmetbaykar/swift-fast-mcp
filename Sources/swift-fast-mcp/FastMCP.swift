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
    var prompts: [any MCPPrompt]
    var samplingEnabled: Bool
    var transportConfig: Transport
    var customLogger: Logger?
    var shutdownSignals: [UnixSignal]
    var onStartHandler: (@Sendable () async -> Void)?
    var onShutdownHandler: (@Sendable () async -> Void)?

    let toolDeduplicator = ToolDeduplicator()
    let resourceDeduplicator = ResourceDeduplicator()
    let promptDeduplicator = PromptDeduplicator()

    public init() {
      self.serverName = ProcessInfo.processInfo.processName
      self.serverVersion = "1.0.0"
      self.tools = []
      self.resources = []
      self.prompts = []
      self.samplingEnabled = false
      self.transportConfig = .stdio
      self.customLogger = nil
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

    public func addPrompts(_ newPrompts: [any MCPPrompt]) -> Builder {
      var copy = self
      copy.prompts = promptDeduplicator.deduplicate(copy.prompts, adding: newPrompts)
      return copy
    }

    public func enableSampling(_ enabled: Bool = true) -> Builder {
      var copy = self
      copy.samplingEnabled = enabled
      return copy
    }

    public func transport(_ transport: Transport) -> Builder {
      var copy = self
      copy.transportConfig = transport
      return copy
    }

    public func logger(_ logger: Logger) -> Builder {
      var copy = self
      copy.customLogger = logger
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
      let logger = customLogger ?? Logger(label: serverName)

      if tools.isEmpty && resources.isEmpty && prompts.isEmpty {
        logger.warning("Server starting with no tools, resources, or prompts registered")
      }

      let capabilities = CapabilitiesBuilder.build(
        hasTools: !tools.isEmpty,
        hasResources: !resources.isEmpty,
        hasPrompts: !prompts.isEmpty,
        hasSampling: samplingEnabled
      )

      let server = Server(
        name: serverName,
        version: serverVersion,
        capabilities: capabilities
      )

      await server.register(tools: tools)
      await server.register(resources: resources)
      await server.register(prompts: prompts)

      let mcpTransport: MCP.Transport = createTransport(logger: logger)

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

    private func createTransport(logger: Logger) -> MCP.Transport {
      switch transportConfig {
      case .stdio:
        return StdioTransport(logger: logger)
      case .inMemory:
        return InMemoryTransport()
      case .custom(let transport):
        return transport
      }
    }
  }
}
