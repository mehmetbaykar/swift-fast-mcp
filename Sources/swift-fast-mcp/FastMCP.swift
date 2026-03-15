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
    var transportConfig: Transport
    var customLogger: Logger?
    var shutdownSignals: [UnixSignal]
    var onStartHandler: (@Sendable () async -> Void)?
    var onShutdownHandler: (@Sendable () async -> Void)?
    var serverTitle: String?
    var serverInstructions: String?
    var serverIcons: [Icon]?
    var completionsEnabled: Bool
    var loggingEnabled: Bool
    var initializeHook: (@Sendable (Client.Info, Client.Capabilities) async throws -> Void)?
    var sessionTimeoutDuration: Duration
    var httpAllowedOrigins: [String]?
    var httpCustomValidators: [any HTTPRequestValidator]

    let toolDeduplicator = ToolDeduplicator()
    let resourceDeduplicator = ResourceDeduplicator()
    let promptDeduplicator = PromptDeduplicator()

    public init() {
      self.serverName = ProcessInfo.processInfo.processName
      self.serverVersion = "1.0.0"
      self.tools = []
      self.resources = []
      self.prompts = []
      self.transportConfig = .stdio
      self.customLogger = nil
      self.shutdownSignals = [.sigterm, .sigint]
      self.onStartHandler = nil
      self.onShutdownHandler = nil
      self.serverTitle = nil
      self.serverInstructions = nil
      self.serverIcons = nil
      self.completionsEnabled = false
      self.loggingEnabled = false
      self.initializeHook = nil
      self.sessionTimeoutDuration = .seconds(3600)
      self.httpAllowedOrigins = nil
      self.httpCustomValidators = []
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

    public func title(_ title: String) -> Builder {
      var copy = self
      copy.serverTitle = title
      return copy
    }

    public func instructions(_ instructions: String) -> Builder {
      var copy = self
      copy.serverInstructions = instructions
      return copy
    }

    public func icons(_ icons: [Icon]) -> Builder {
      var copy = self
      copy.serverIcons = icons
      return copy
    }

    public func enableCompletions(_ enabled: Bool = true) -> Builder {
      var copy = self
      copy.completionsEnabled = enabled
      return copy
    }

    public func enableLogging(_ enabled: Bool = true) -> Builder {
      var copy = self
      copy.loggingEnabled = enabled
      return copy
    }

    /// Called when a client sends an initialize request. Useful for per-client auth or setup,
    /// especially in HTTP mode where multiple clients connect.
    public func onInitialize(
      _ handler: @escaping @Sendable (Client.Info, Client.Capabilities) async throws -> Void
    ) -> Builder {
      var copy = self
      copy.initializeHook = handler
      return copy
    }

    /// Only applies to .http transport with .stateful mode. Default: 3600 seconds.
    public func sessionTimeout(_ timeout: Duration) -> Builder {
      var copy = self
      copy.sessionTimeoutDuration = timeout
      return copy
    }

    /// Only applies to .http transport. Customize origin allowlist and add custom validators (e.g., auth).
    public func httpValidation(
      allowedOrigins: [String]? = nil,
      customValidators: [any HTTPRequestValidator] = []
    ) -> Builder {
      var copy = self
      copy.httpAllowedOrigins = allowedOrigins
      copy.httpCustomValidators = customValidators
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
        hasCompletions: completionsEnabled,
        hasLogging: loggingEnabled
      )

      switch transportConfig {
      case .http(let mode, let host, let port, let endpoint):
        let serverName = self.serverName
        let serverVersion = self.serverVersion
        let serverTitle = self.serverTitle
        let serverInstructions = self.serverInstructions
        let tools = self.tools
        let resources = self.resources
        let prompts = self.prompts
        let initializeHook = self.initializeHook

        let httpConfig = FastMCPHTTPServer.Configuration(
          host: host,
          port: port,
          endpoint: endpoint,
          sessionTimeout: TimeInterval(sessionTimeoutDuration.components.seconds)
        )

        let httpServer: FastMCPHTTPServer
        switch mode {
        case .stateful:
          httpServer = FastMCPHTTPServer(
            configuration: httpConfig,
            validationPipeline: nil,
            serverFactory: { sessionID, sessionTransport in
              let server = Server(
                name: serverName,
                version: serverVersion,
                title: serverTitle,
                instructions: serverInstructions,
                capabilities: capabilities
              )
              await server.register(tools: tools)
              await server.register(resources: resources)
              await server.register(prompts: prompts)
              try await server.start(transport: sessionTransport, initializeHook: initializeHook)
              return server
            },
            logger: logger
          )
        case .stateless:
          httpServer = FastMCPHTTPServer(
            configuration: httpConfig,
            validationPipeline: nil,
            statelessServerFactory: { sessionTransport in
              let server = Server(
                name: serverName,
                version: serverVersion,
                title: serverTitle,
                instructions: serverInstructions,
                capabilities: capabilities
              )
              await server.register(tools: tools)
              await server.register(resources: resources)
              await server.register(prompts: prompts)
              try await server.start(transport: sessionTransport, initializeHook: initializeHook)
              return server
            },
            logger: logger
          )
        }

        try await httpServer.start()

      default:
        let server = Server(
          name: serverName,
          version: serverVersion,
          title: serverTitle,
          instructions: serverInstructions,
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
          onShutdown: onShutdownHandler,
          initializeHook: initializeHook
        )

        let serviceGroup = ServiceGroup(
          services: [service],
          gracefulShutdownSignals: shutdownSignals,
          logger: logger
        )

        try await serviceGroup.run()
      }
    }

    private func createTransport(logger: Logger) -> MCP.Transport {
      switch transportConfig {
      case .stdio:
        return StdioTransport(logger: logger)
      case .inMemory:
        return InMemoryTransport()
      case .http:
        fatalError(
          "HTTP transport is handled directly in run() and should not reach createTransport")
      case .custom(let transport):
        return transport
      }
    }
  }
}
