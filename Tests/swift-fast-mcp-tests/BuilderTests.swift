import ExampleTools
import FastMCPAIBridge
import Foundation
import Logging
import MCP
import Testing
import UnixSignals

@testable import FastMCP

@Suite("FastMCP Builder Tests")
struct BuilderTests {

  @Test
  func builderUsesProcessNameAsDefaultServerName() {
    let builder = FastMCP.builder()
    #expect(builder.serverName == ProcessInfo.processInfo.processName)
  }

  @Test
  func builderUsesDefaultVersion() {
    let builder = FastMCP.builder()
    #expect(builder.serverVersion == "1.0.0")
  }

  @Test
  func builderUsesStdioTransportByDefault() {
    let builder = FastMCP.builder()
    guard case .stdio = builder.transportConfig else {
      Issue.record("Expected stdio transport by default")
      return
    }
  }

  @Test
  func builderUsesNoLoggerByDefault() {
    let builder = FastMCP.builder()
    #expect(builder.customLogger == nil)
  }

  @Test
  func builderUsesDefaultShutdownSignals() {
    let builder = FastMCP.builder()
    #expect(builder.shutdownSignals.contains(.sigterm))
    #expect(builder.shutdownSignals.contains(.sigint))
  }

  @Test
  func builderStartsWithEmptyTools() {
    let builder = FastMCP.builder()
    #expect(builder.hubTools.isEmpty)
  }

  @Test
  func builderStartsWithEmptyResources() {
    let builder = FastMCP.builder()
    #expect(builder.resources.isEmpty)
  }

  @Test
  func builderStartsWithEmptyPrompts() {
    let builder = FastMCP.builder()
    #expect(builder.prompts.isEmpty)
  }

  @Test
  func nameMethodUpdatesServerName() {
    let builder = FastMCP.builder().name("CustomServer")
    #expect(builder.serverName == "CustomServer")
  }

  @Test
  func versionMethodUpdatesServerVersion() {
    let builder = FastMCP.builder().version("2.5.0")
    #expect(builder.serverVersion == "2.5.0")
  }

  @Test
  func addToolsMethodAddsTools() throws {
    let builder = try FastMCP.builder().addTools([WeatherTool(), MathTool()])
    #expect(builder.hubTools.count == 2)
    let toolNames = builder.hubTools.map { $0.name }
    #expect(toolNames.contains("weather"))
    #expect(toolNames.contains("math"))
  }

  @Test
  func addToolsMethodRejectsDuplicateTools() throws {
    let builder = try FastMCP.builder().addTools([WeatherTool()])
    #expect(throws: HubBridgeError.self) {
      _ = try builder.addTools([WeatherTool(), MathTool()])
    }
  }

  @Test
  func addPromptsMethodAddsPrompts() {
    let builder = FastMCP.builder().addPrompts([GreetingPrompt()])
    #expect(builder.prompts.count == 1)
    #expect(builder.prompts.first?.name == "greeting")
  }

  @Test
  func addPromptsMethodDeduplicatesPromptsWithSameName() {
    let builder = FastMCP.builder()
      .addPrompts([GreetingPrompt()])
      .addPrompts([GreetingPrompt()])
    #expect(builder.prompts.count == 1)
  }

  @Test
  func transportMethodUpdatesTransportConfig() {
    let builder = FastMCP.builder().transport(.inMemory)
    guard case .inMemory = builder.transportConfig else {
      Issue.record("Expected inMemory transport")
      return
    }
  }

  @Test
  func loggerMethodSetsCustomLogger() {
    var logger = Logger(label: "test")
    logger.logLevel = .debug
    let builder = FastMCP.builder().logger(logger)
    #expect(builder.customLogger != nil)
  }

  @Test
  func shutdownSignalsMethodUpdatesSignals() {
    let builder = FastMCP.builder().shutdownSignals([.sigterm])
    #expect(builder.shutdownSignals.count == 1)
    #expect(builder.shutdownSignals.contains(.sigterm))
  }

  @Test
  func onStartMethodSetsHandler() {
    let builder = FastMCP.builder().onStart {}
    #expect(builder.onStartHandler != nil)
  }

  @Test
  func onShutdownMethodSetsHandler() {
    let builder = FastMCP.builder().onShutdown {}
    #expect(builder.onShutdownHandler != nil)
  }

  @Test
  func builderCreatesNewInstanceOnEachMethod() {
    let original = FastMCP.builder().name("Original")
    let modified = original.name("Modified")

    #expect(original.serverName == "Original")
    #expect(modified.serverName == "Modified")
  }

  @Test
  func inMemoryTransportIsAvailable() {
    let builder = FastMCP.builder().transport(.inMemory)
    guard case .inMemory = builder.transportConfig else {
      Issue.record("Expected inMemory transport")
      return
    }
  }

  // MARK: - New builder fields

  @Test("Builder stores title field")
  func titleMethodUpdatesServerTitle() {
    let builder = FastMCP.builder().title("My Display Name")
    #expect(builder.serverTitle == "My Display Name")
  }

  @Test("Builder title defaults to nil")
  func titleDefaultsToNil() {
    let builder = FastMCP.builder()
    #expect(builder.serverTitle == nil)
  }

  @Test("Builder stores instructions field")
  func instructionsMethodUpdatesServerInstructions() {
    let builder = FastMCP.builder().instructions("Use this server for weather lookups.")
    #expect(builder.serverInstructions == "Use this server for weather lookups.")
  }

  @Test("Builder instructions defaults to nil")
  func instructionsDefaultsToNil() {
    let builder = FastMCP.builder()
    #expect(builder.serverInstructions == nil)
  }

  @Test("Builder stores icons field")
  func iconsMethodUpdatesServerIcons() {
    let icons = [Icon(src: "https://example.com/icon.png", mimeType: "image/png")]
    let builder = FastMCP.builder().icons(icons)
    #expect(builder.serverIcons != nil)
    #expect(builder.serverIcons?.count == 1)
    #expect(builder.serverIcons?.first?.src == "https://example.com/icon.png")
  }

  @Test("Builder icons defaults to nil")
  func iconsDefaultsToNil() {
    let builder = FastMCP.builder()
    #expect(builder.serverIcons == nil)
  }

  @Test("Builder default sessionTimeout is .seconds(3600)")
  func defaultSessionTimeout() {
    let builder = FastMCP.builder()
    #expect(builder.sessionTimeoutDuration == .seconds(3600))
  }

  @Test("Builder custom sessionTimeout is stored")
  func customSessionTimeout() {
    let builder = FastMCP.builder().sessionTimeout(.seconds(1800))
    #expect(builder.sessionTimeoutDuration == .seconds(1800))
  }

  @Test("Builder enableCompletions stores true")
  func enableCompletionsStoresTrue() {
    let builder = FastMCP.builder().enableCompletions()
    #expect(builder.completionsEnabled == true)
  }

  @Test("Builder completions defaults to false")
  func completionsDefaultsToFalse() {
    let builder = FastMCP.builder()
    #expect(builder.completionsEnabled == false)
  }

  @Test("Builder enableLogging stores true")
  func enableLoggingStoresTrue() {
    let builder = FastMCP.builder().enableLogging()
    #expect(builder.loggingEnabled == true)
  }

  @Test("Builder logging defaults to false")
  func loggingDefaultsToFalse() {
    let builder = FastMCP.builder()
    #expect(builder.loggingEnabled == false)
  }

  @Test("Builder http transport stores mode, host, port, endpoint")
  func httpTransportStoresAllFields() {
    let builder = FastMCP.builder().transport(
      .http(mode: .stateless, host: "0.0.0.0", port: 9090, endpoint: "/api/mcp"))
    guard case .http(let mode, let host, let port, let endpoint) = builder.transportConfig else {
      Issue.record("Expected http transport")
      return
    }
    guard case .stateless = mode else {
      Issue.record("Expected stateless mode")
      return
    }
    #expect(host == "0.0.0.0")
    #expect(port == 9090)
    #expect(endpoint == "/api/mcp")
  }

  @Test("Builder httpValidation stores allowedOrigins")
  func httpValidationStoresAllowedOrigins() {
    let builder = FastMCP.builder().httpValidation(allowedOrigins: [
      "https://example.com", "https://app.example.com",
    ])
    #expect(builder.httpAllowedOrigins != nil)
    #expect(builder.httpAllowedOrigins?.count == 2)
    #expect(builder.httpAllowedOrigins?.contains("https://example.com") == true)
    #expect(builder.httpAllowedOrigins?.contains("https://app.example.com") == true)
  }

  @Test("Builder httpAllowedOrigins defaults to nil")
  func httpAllowedOriginsDefaultsToNil() {
    let builder = FastMCP.builder()
    #expect(builder.httpAllowedOrigins == nil)
  }

  @Test("Builder onInitialize stores handler")
  func onInitializeStoresHandler() {
    let builder = FastMCP.builder().onInitialize { clientInfo, capabilities in
      // no-op
    }
    #expect(builder.initializeHook != nil)
  }

  @Test("Builder onInitialize defaults to nil")
  func onInitializeDefaultsToNil() {
    let builder = FastMCP.builder()
    #expect(builder.initializeHook == nil)
  }

  @Test("Builder chain works with all new options")
  func builderChainWorksWithAllNewOptions() throws {
    var logger = Logger(label: "FullServer")
    logger.logLevel = .warning

    let icons = [Icon(src: "https://example.com/icon.png")]

    let builder = try FastMCP.builder()
      .name("FullServer")
      .version("3.0.0")
      .title("Full Server Display Name")
      .instructions("Instructions for the LLM.")
      .icons(icons)
      .addTools([WeatherTool()])
      .addTools([MathTool()])
      .addPrompts([GreetingPrompt()])
      .enableCompletions()
      .enableLogging()
      .transport(.http(port: 8080))
      .sessionTimeout(.seconds(7200))
      .httpValidation(allowedOrigins: ["https://example.com"])
      .logger(logger)
      .shutdownSignals([.sigterm])
      .onInitialize { _, _ in }
      .onStart {}
      .onShutdown {}

    #expect(builder.serverName == "FullServer")
    #expect(builder.serverVersion == "3.0.0")
    #expect(builder.serverTitle == "Full Server Display Name")
    #expect(builder.serverInstructions == "Instructions for the LLM.")
    #expect(builder.serverIcons?.count == 1)
    #expect(builder.hubTools.count == 2)
    #expect(builder.prompts.count == 1)
    #expect(builder.completionsEnabled == true)
    #expect(builder.loggingEnabled == true)
    #expect(builder.sessionTimeoutDuration == .seconds(7200))
    #expect(builder.httpAllowedOrigins?.count == 1)
    #expect(builder.customLogger != nil)
    #expect(builder.shutdownSignals == [.sigterm])
    #expect(builder.initializeHook != nil)
    #expect(builder.onStartHandler != nil)
    #expect(builder.onShutdownHandler != nil)
  }
}

@Suite("CapabilitiesBuilder Tests")
struct CapabilitiesBuilderTests {

  @Test("Builds with completions and logging, no sampling")
  func buildsWithCompletionsAndLogging() {
    let capabilities = CapabilitiesBuilder.build(
      hasTools: true,
      hasResources: true,
      hasPrompts: true,
      hasCompletions: true,
      hasLogging: true
    )

    #expect(capabilities.tools != nil)
    #expect(capabilities.resources != nil)
    #expect(capabilities.prompts != nil)
    #expect(capabilities.completions != nil)
    #expect(capabilities.logging != nil)
  }

  @Test("Builds without completions and logging when not requested")
  func buildsWithoutCompletionsAndLogging() {
    let capabilities = CapabilitiesBuilder.build(
      hasTools: true,
      hasResources: false,
      hasPrompts: false
    )

    #expect(capabilities.tools != nil)
    #expect(capabilities.resources == nil)
    #expect(capabilities.prompts == nil)
    #expect(capabilities.completions == nil)
    #expect(capabilities.logging == nil)
  }

  @Test("Builds with no capabilities when nothing is enabled")
  func buildsWithNoCapabilities() {
    let capabilities = CapabilitiesBuilder.build(
      hasTools: false,
      hasResources: false
    )

    #expect(capabilities.tools == nil)
    #expect(capabilities.resources == nil)
    #expect(capabilities.prompts == nil)
    #expect(capabilities.completions == nil)
    #expect(capabilities.logging == nil)
  }
}
