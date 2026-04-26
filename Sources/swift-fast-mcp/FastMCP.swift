import FastMCPAIBridge
import Foundation
import Logging
import MCP
import ServiceLifecycle
import SwiftAIHub
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
    var hubTools: [any SwiftAIHub.Tool]
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
    var handle: FastMCPServerHandle?
    var upstreamMCPServers: [UpstreamMCPServerConfiguration]

    let resourceDeduplicator = ResourceDeduplicator()
    let promptDeduplicator = PromptDeduplicator()

    public init() {
      self.serverName = ProcessInfo.processInfo.processName
      self.serverVersion = "1.0.0"
      self.hubTools = []
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
      self.handle = nil
      self.upstreamMCPServers = []
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

    public func addTools(_ newTools: [any SwiftAIHub.Tool]) throws -> Builder {
      var copy = self
      var existingNames = Set(copy.hubTools.map { $0.name })
      for tool in newTools {
        if existingNames.contains(tool.name) {
          throw HubBridgeError.duplicateTool(name: tool.name)
        }
        existingNames.insert(tool.name)
        copy.hubTools.append(tool)
      }
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

    public func onInitialize(
      _ handler: @escaping @Sendable (Client.Info, Client.Capabilities) async throws -> Void
    ) -> Builder {
      var copy = self
      copy.initializeHook = handler
      return copy
    }

    public func sessionTimeout(_ timeout: Duration) -> Builder {
      var copy = self
      copy.sessionTimeoutDuration = timeout
      return copy
    }

    public func httpValidation(
      allowedOrigins: [String]? = nil,
      customValidators: [any HTTPRequestValidator] = []
    ) -> Builder {
      var copy = self
      copy.httpAllowedOrigins = allowedOrigins
      copy.httpCustomValidators = customValidators
      return copy
    }

    public func serverHandle(_ handle: FastMCPServerHandle) -> Builder {
      var copy = self
      copy.handle = handle
      return copy
    }

    public func addUpstreamMCPServer(
      name: String,
      transport: UpstreamMCPTransport,
      toolNamePrefix: String? = nil
    ) throws -> Builder {
      try addUpstreamMCPServers([
        UpstreamMCPServerConfiguration(
          name: name,
          transport: transport,
          toolNamePrefix: toolNamePrefix
        )
      ])
    }

    public func addUpstreamMCPServers(_ configurations: [UpstreamMCPServerConfiguration]) throws
      -> Builder
    {
      var copy = self
      var existingNames = Set(copy.upstreamMCPServers.map(\.name))
      for configuration in configurations {
        if !existingNames.insert(configuration.name).inserted {
          throw FastMCPError.invalidConfiguration(
            "Upstream MCP server '\(configuration.name)' is already registered")
        }
      }
      copy.upstreamMCPServers.append(contentsOf: configurations)
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

      if hubTools.isEmpty && resources.isEmpty && prompts.isEmpty && handle == nil {
        logger.warning("Server starting with no tools, resources, or prompts registered")
      }

      let listChanged = handle != nil
      let hubToolAdapter = try HubToolAdapter(tools: hubTools)
      let upstreamManager = UpstreamMCPManager(toolAdapter: hubToolAdapter, logger: logger)
      for upstream in upstreamMCPServers {
        try await upstreamManager.addServer(upstream)
      }

      let capabilities = CapabilitiesBuilder.build(
        hasTools: !hubTools.isEmpty || !upstreamMCPServers.isEmpty || listChanged,
        hasResources: !resources.isEmpty || listChanged,
        hasPrompts: !prompts.isEmpty || listChanged,
        hasCompletions: completionsEnabled,
        hasLogging: loggingEnabled,
        listChanged: listChanged
      )

      if let handle {
        await handle.configure(
          toolAdapter: hubToolAdapter,
          upstreamManager: upstreamManager,
          resources: resources,
          prompts: prompts
        )
      }

      switch transportConfig {
      case .http(let mode, let host, let port, let endpoint):
        let serverName = self.serverName
        let serverVersion = self.serverVersion
        let serverTitle = self.serverTitle
        let serverInstructions = self.serverInstructions
        let resources = self.resources
        let prompts = self.prompts
        let initializeHook = self.initializeHook
        let handle = self.handle
        let loggingEnabled = self.loggingEnabled
        let upstreamManager = upstreamManager

        let httpConfig = FastMCPHTTPServer.Configuration(
          host: host,
          port: port,
          endpoint: endpoint,
          sessionTimeout: TimeInterval(sessionTimeoutDuration.components.seconds)
        )

        let validationPipeline: (any HTTPRequestValidationPipeline)? = {
          var validators: [any HTTPRequestValidator] = []
          if let allowed = httpAllowedOrigins, !allowed.isEmpty {
            validators.append(OriginValidator(allowedHosts: [host], allowedOrigins: allowed))
          }
          validators.append(contentsOf: httpCustomValidators)
          return validators.isEmpty ? nil : StandardValidationPipeline(validators: validators)
        }()

        let httpServer: FastMCPHTTPServer
        switch mode {
        case .stateful:
          httpServer = FastMCPHTTPServer(
            configuration: httpConfig,
            validationPipeline: validationPipeline,
            serverFactory: { sessionID, sessionTransport in
              let server = Server(
                name: serverName,
                version: serverVersion,
                title: serverTitle,
                instructions: serverInstructions,
                capabilities: capabilities
              )

              if let handle {
                await handle.registerHTTPSession(server)
              } else {
                await server.register(hubTools: hubToolAdapter)
                await server.register(resources: resources)
                await server.register(prompts: prompts)
              }

              if loggingEnabled {
                await server.withMethodHandler(SetLoggingLevel.self) { _ in Empty() }
              }

              try await server.start(transport: sessionTransport, initializeHook: initializeHook)
              if let handle {
                await handle.activateHTTPSession(server)
              }
              return server
            },
            logger: logger
          )
        case .stateless:
          httpServer = FastMCPHTTPServer(
            configuration: httpConfig,
            validationPipeline: validationPipeline,
            statelessServerFactory: { sessionTransport in
              let server = Server(
                name: serverName,
                version: serverVersion,
                title: serverTitle,
                instructions: serverInstructions,
                capabilities: capabilities
              )

              if let handle {
                await handle.registerHTTPSession(server)
              } else {
                await server.register(hubTools: hubToolAdapter)
                await server.register(resources: resources)
                await server.register(prompts: prompts)
              }

              if loggingEnabled {
                await server.withMethodHandler(SetLoggingLevel.self) { _ in Empty() }
              }

              try await server.start(transport: sessionTransport, initializeHook: initializeHook)
              if let handle {
                await handle.activateHTTPSession(server)
              }
              return server
            },
            logger: logger
          )
        }

        let httpService = HTTPFastMCPService(
          httpServer: httpServer,
          logger: logger,
          upstreamManager: upstreamManager,
          onStart: onStartHandler,
          onShutdown: onShutdownHandler
        )
        let serviceGroup = ServiceGroup(
          services: [httpService],
          gracefulShutdownSignals: shutdownSignals,
          logger: logger
        )
        try await serviceGroup.run()

      default:
        let server = Server(
          name: serverName,
          version: serverVersion,
          title: serverTitle,
          instructions: serverInstructions,
          capabilities: capabilities
        )

        await server.register(hubTools: hubToolAdapter)
        await server.register(resources: resources)
        await server.register(prompts: prompts)

        if loggingEnabled {
          await server.withMethodHandler(SetLoggingLevel.self) { _ in Empty() }
        }

        if let handle {
          await handle.registerServer(server)
        }

        let mcpTransport: MCP.Transport = createTransport(logger: logger)

        let service = FastMCPService(
          server: server,
          transport: mcpTransport,
          logger: logger,
          upstreamManager: upstreamManager,
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
