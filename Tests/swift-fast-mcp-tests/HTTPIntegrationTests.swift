import Foundation
import Testing

@testable import FastMCP

@Suite("HTTP Integration Tests")
struct HTTPIntegrationTests {

  @Test("HTTP transport enum stores configuration correctly")
  func httpTransportConfiguration() {
    let transport = Transport.http(mode: .stateful, host: "127.0.0.1", port: 3000, endpoint: "/mcp")

    guard case .http(let mode, let host, let port, let endpoint) = transport else {
      Issue.record("Expected http transport")
      return
    }
    guard case .stateful = mode else {
      Issue.record("Expected stateful mode")
      return
    }
    #expect(host == "127.0.0.1")
    #expect(port == 3000)
    #expect(endpoint == "/mcp")
  }

  @Test("HTTPMode defaults to stateful")
  func httpModeDefault() {
    // When using .http() with no mode argument, the default should be .stateful
    let transport = Transport.http()

    guard case .http(let mode, _, _, _) = transport else {
      Issue.record("Expected http transport")
      return
    }
    guard case .stateful = mode else {
      Issue.record("Expected default mode to be stateful")
      return
    }
  }

  @Test("HTTP transport with custom port")
  func httpCustomPort() {
    let transport = Transport.http(port: 9090)

    guard case .http(_, _, let port, _) = transport else {
      Issue.record("Expected http transport")
      return
    }
    #expect(port == 9090)
  }

  @Test("HTTP transport with stateless mode")
  func httpStatelessMode() {
    let transport = Transport.http(mode: .stateless)

    guard case .http(let mode, _, _, _) = transport else {
      Issue.record("Expected http transport")
      return
    }
    guard case .stateless = mode else {
      Issue.record("Expected stateless mode")
      return
    }
  }

  @Test("HTTP transport with all custom parameters")
  func httpAllCustomParameters() {
    let transport = Transport.http(
      mode: .stateless, host: "0.0.0.0", port: 9090, endpoint: "/api/mcp")

    guard case .http(let mode, let host, let port, let endpoint) = transport else {
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

  @Test("Builder with HTTP transport preserves all settings")
  func builderWithHTTPTransport() {
    let builder = FastMCP.builder()
      .name("HTTP Test Server")
      .version("2.0.0")
      .title("HTTP Test")
      .instructions("Test instructions for HTTP server.")
      .enableCompletions()
      .enableLogging()
      .transport(.http(mode: .stateful, host: "0.0.0.0", port: 8080, endpoint: "/mcp"))
      .sessionTimeout(.seconds(1800))
      .httpValidation(allowedOrigins: ["https://example.com"])

    // Verify server metadata
    #expect(builder.serverName == "HTTP Test Server")
    #expect(builder.serverVersion == "2.0.0")
    #expect(builder.serverTitle == "HTTP Test")
    #expect(builder.serverInstructions == "Test instructions for HTTP server.")

    // Verify capabilities
    #expect(builder.completionsEnabled == true)
    #expect(builder.loggingEnabled == true)

    // Verify transport configuration
    guard case .http(let mode, let host, let port, let endpoint) = builder.transportConfig else {
      Issue.record("Expected http transport")
      return
    }
    guard case .stateful = mode else {
      Issue.record("Expected stateful mode")
      return
    }
    #expect(host == "0.0.0.0")
    #expect(port == 8080)
    #expect(endpoint == "/mcp")

    // Verify HTTP-specific settings
    #expect(builder.sessionTimeoutDuration == .seconds(1800))
    #expect(builder.httpAllowedOrigins?.count == 1)
    #expect(builder.httpAllowedOrigins?.first == "https://example.com")
  }

  @Test("HTTP transport default host is 127.0.0.1")
  func httpDefaultHost() {
    let transport = Transport.http()

    guard case .http(_, let host, _, _) = transport else {
      Issue.record("Expected http transport")
      return
    }
    #expect(host == "127.0.0.1")
  }

  @Test("HTTP transport default port is 3000")
  func httpDefaultPort() {
    let transport = Transport.http()

    guard case .http(_, _, let port, _) = transport else {
      Issue.record("Expected http transport")
      return
    }
    #expect(port == 3000)
  }

  @Test("HTTP transport default endpoint is /mcp")
  func httpDefaultEndpoint() {
    let transport = Transport.http()

    guard case .http(_, _, _, let endpoint) = transport else {
      Issue.record("Expected http transport")
      return
    }
    #expect(endpoint == "/mcp")
  }

  @Test("HTTPMode enum has stateful case")
  func httpModeStateful() {
    let mode = HTTPMode.stateful
    guard case .stateful = mode else {
      Issue.record("Expected stateful mode")
      return
    }
  }

  @Test("HTTPMode enum has stateless case")
  func httpModeStateless() {
    let mode = HTTPMode.stateless
    guard case .stateless = mode else {
      Issue.record("Expected stateless mode")
      return
    }
  }
}
