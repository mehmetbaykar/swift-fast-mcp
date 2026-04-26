import ExampleTools
import FastMCPAIBridge
import Foundation
import Logging
import MCP
import SwiftAIHub
import SwiftAIHubMCP
import Testing
import UnixSignals

@testable import FastMCP

@Suite("FastMCP Builder Tests")
struct BuilderTests {

  @Test func `builder uses process name as default server name`() {
    let builder = FastMCP.builder()
    #expect(builder.serverName == ProcessInfo.processInfo.processName)
  }

  @Test func `builder uses default version`() {
    let builder = FastMCP.builder()
    #expect(builder.serverVersion == "1.0.0")
  }

  @Test func `builder uses stdio transport by default`() {
    let builder = FastMCP.builder()
    guard case .stdio = builder.transportConfig else {
      Issue.record("Expected stdio transport by default")
      return
    }
  }

  @Test func `builder uses no logger by default`() {
    let builder = FastMCP.builder()
    #expect(builder.customLogger == nil)
  }

  @Test func `builder uses default shutdown signals`() {
    let builder = FastMCP.builder()
    #expect(builder.shutdownSignals.contains(.sigterm))
    #expect(builder.shutdownSignals.contains(.sigint))
  }

  @Test func `builder starts with empty tools`() {
    let builder = FastMCP.builder()
    #expect(builder.hubTools.isEmpty)
  }

  @Test func `builder starts with empty resources`() {
    let builder = FastMCP.builder()
    #expect(builder.resources.isEmpty)
  }

  @Test func `builder starts with empty prompts`() {
    let builder = FastMCP.builder()
    #expect(builder.prompts.isEmpty)
  }

  @Test func `name method updates server name`() {
    let builder = FastMCP.builder().name("CustomServer")
    #expect(builder.serverName == "CustomServer")
  }

  @Test func `version method updates server version`() {
    let builder = FastMCP.builder().version("2.5.0")
    #expect(builder.serverVersion == "2.5.0")
  }

  @Test func `add tools method adds tools`() throws {
    let builder = try FastMCP.builder().addTools([WeatherTool(), MathTool()])
    #expect(builder.hubTools.count == 2)
    let toolNames = builder.hubTools.map { $0.name }
    #expect(toolNames.contains("weather"))
    #expect(toolNames.contains("math"))
  }

  @Test func `add tools accepts tool source`() async throws {
    let source = StaticToolSource(tools: [WeatherTool(), MathTool()])
    let builder = try await FastMCP.builder().addTools(source)

    #expect(builder.hubTools.map(\.name).sorted() == ["math", "weather"])
  }

  @Test func `add MCP tool provider resolves tools`() async throws {
    let provider = StaticToolSource(tools: [WeatherTool()])
    let builder = try await FastMCP.builder().addMCPToolProvider(provider)

    #expect(builder.hubTools.map(\.name) == ["weather"])
  }

  @Test func `add tools method rejects duplicate tools`() throws {
    let builder = try FastMCP.builder().addTools([WeatherTool()])
    #expect(throws: HubBridgeError.self) {
      _ = try builder.addTools([WeatherTool(), MathTool()])
    }
  }

  @Test func `add prompts method adds prompts`() {
    let builder = FastMCP.builder().addPrompts([GreetingPrompt()])
    #expect(builder.prompts.count == 1)
    #expect(builder.prompts.first?.name == "greeting")
  }

  @Test func `add prompts method deduplicates prompts with same name`() {
    let builder = FastMCP.builder()
      .addPrompts([GreetingPrompt()])
      .addPrompts([GreetingPrompt()])
    #expect(builder.prompts.count == 1)
  }

  @Test func `transport method updates transport config`() {
    let builder = FastMCP.builder().transport(.inMemory)
    guard case .inMemory = builder.transportConfig else {
      Issue.record("Expected inMemory transport")
      return
    }
  }

  @Test func `logger method sets custom logger`() {
    var logger = Logger(label: "test")
    logger.logLevel = .debug
    let builder = FastMCP.builder().logger(logger)
    #expect(builder.customLogger != nil)
  }

  @Test func `shutdown signals method updates signals`() {
    let builder = FastMCP.builder().shutdownSignals([.sigterm])
    #expect(builder.shutdownSignals.count == 1)
    #expect(builder.shutdownSignals.contains(.sigterm))
  }

  @Test func `on start method sets handler`() {
    let builder = FastMCP.builder().onStart {}
    #expect(builder.onStartHandler != nil)
  }

  @Test func `on shutdown method sets handler`() {
    let builder = FastMCP.builder().onShutdown {}
    #expect(builder.onShutdownHandler != nil)
  }

  @Test func `builder creates new instance on each method`() {
    let original = FastMCP.builder().name("Original")
    let modified = original.name("Modified")

    #expect(original.serverName == "Original")
    #expect(modified.serverName == "Modified")
  }

  @Test func `in memory transport is available`() {
    let builder = FastMCP.builder().transport(.inMemory)
    guard case .inMemory = builder.transportConfig else {
      Issue.record("Expected inMemory transport")
      return
    }
  }

  // MARK: - New builder fields

  @Test
  func `Builder stores title field`() {
    let builder = FastMCP.builder().title("My Display Name")
    #expect(builder.serverTitle == "My Display Name")
  }

  @Test
  func `Builder title defaults to nil`() {
    let builder = FastMCP.builder()
    #expect(builder.serverTitle == nil)
  }

  @Test
  func `Builder stores instructions field`() {
    let builder = FastMCP.builder().instructions("Use this server for weather lookups.")
    #expect(builder.serverInstructions == "Use this server for weather lookups.")
  }

  @Test
  func `Builder instructions defaults to nil`() {
    let builder = FastMCP.builder()
    #expect(builder.serverInstructions == nil)
  }

  @Test
  func `Builder stores icons field`() {
    let icons = [Icon(src: "https://example.com/icon.png", mimeType: "image/png")]
    let builder = FastMCP.builder().icons(icons)
    #expect(builder.serverIcons != nil)
    #expect(builder.serverIcons?.count == 1)
    #expect(builder.serverIcons?.first?.src == "https://example.com/icon.png")
  }

  @Test
  func `Builder icons defaults to nil`() {
    let builder = FastMCP.builder()
    #expect(builder.serverIcons == nil)
  }

  @Test
  func `Builder default sessionTimeout is .seconds(3600)`() {
    let builder = FastMCP.builder()
    #expect(builder.sessionTimeoutDuration == .seconds(3600))
  }

  @Test
  func `Builder custom sessionTimeout is stored`() {
    let builder = FastMCP.builder().sessionTimeout(.seconds(1800))
    #expect(builder.sessionTimeoutDuration == .seconds(1800))
  }

  @Test
  func `Builder enableCompletions stores true`() {
    let builder = FastMCP.builder().enableCompletions()
    #expect(builder.completionsEnabled == true)
  }

  @Test
  func `Builder completions defaults to false`() {
    let builder = FastMCP.builder()
    #expect(builder.completionsEnabled == false)
  }

  @Test
  func `Builder enableLogging stores true`() {
    let builder = FastMCP.builder().enableLogging()
    #expect(builder.loggingEnabled == true)
  }

  @Test
  func `Builder logging defaults to false`() {
    let builder = FastMCP.builder()
    #expect(builder.loggingEnabled == false)
  }

  @Test
  func `Builder http transport stores mode, host, port, endpoint`() {
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

  @Test
  func `Builder httpValidation stores allowedOrigins`() {
    let builder = FastMCP.builder().httpValidation(allowedOrigins: [
      "https://example.com", "https://app.example.com",
    ])
    #expect(builder.httpAllowedOrigins != nil)
    #expect(builder.httpAllowedOrigins?.count == 2)
    #expect(builder.httpAllowedOrigins?.contains("https://example.com") == true)
    #expect(builder.httpAllowedOrigins?.contains("https://app.example.com") == true)
  }

  @Test
  func `Builder httpAllowedOrigins defaults to nil`() {
    let builder = FastMCP.builder()
    #expect(builder.httpAllowedOrigins == nil)
  }

  @Test
  func `Builder onInitialize stores handler`() {
    let builder = FastMCP.builder().onInitialize { clientInfo, capabilities in
      // no-op
    }
    #expect(builder.initializeHook != nil)
  }

  @Test
  func `Builder onInitialize defaults to nil`() {
    let builder = FastMCP.builder()
    #expect(builder.initializeHook == nil)
  }

  @Test
  func `Builder chain works with all new options`() throws {
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

private struct StaticToolSource: MCPToolProviderProtocol {
  let tools: [any SwiftAIHub.Tool]

  var name: String { "static" }
  var toolNamePrefix: String? { nil }

  func makeConfiguration() async throws -> MCPToolProvider.Configuration {
    MCPToolProvider.Configuration(
      name: name,
      transport: .streamableHTTP(
        endpoint: URL(string: "https://example.com/mcp")!,
        headers: { [:] },
        streaming: true
      )
    )
  }

  func resolveTools() async throws -> [any SwiftAIHub.Tool] {
    tools
  }
}

@Suite("CapabilitiesBuilder Tests")
struct CapabilitiesBuilderTests {

  @Test
  func `Builds with completions and logging, no sampling`() {
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

  @Test
  func `Builds without completions and logging when not requested`() {
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

  @Test
  func `Builds with no capabilities when nothing is enabled`() {
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
