import ExampleTools
import FastMCPAIBridge
import MCP
import SwiftAIHub
import Testing

@testable import FastMCP

// Regression tests for P2: duplicate tool-name registration must surface an
// error instead of silently overwriting the earlier tool. Covers the three
// registration sites identified in swift-fast-mcp:
//
//   * HubToolAdapter(tools:) — eager batch registration.
//   * HubToolAdapter.register — dynamic single registration.
//   * FastMCP.Builder.addTools — builder surface.
//
// The shared fixture uses two distinct WeatherTool() instances whose computed
// @Tool name both resolve to "weather".

@Suite("Duplicate tool-name registration is rejected")
struct DuplicateToolRegistrationTests {

  @Test
  func `HubToolAdapter(tools:) throws duplicateTool on batch collision`() async throws {
    #expect(throws: HubBridgeError.self) {
      _ = try HubToolAdapter(tools: [WeatherTool(), WeatherTool()])
    }

    do {
      _ = try HubToolAdapter(tools: [WeatherTool(), WeatherTool()])
      Issue.record("Expected HubBridgeError.duplicateTool")
    } catch HubBridgeError.duplicateTool(let name) {
      #expect(name == "weather")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func `HubToolAdapter.register throws duplicateTool on dynamic collision`() async throws {
    let adapter = try HubToolAdapter(tools: [WeatherTool()])

    await #expect(throws: HubBridgeError.self) {
      try await adapter.register(WeatherTool())
    }

    do {
      try await adapter.register(WeatherTool())
      Issue.record("Expected HubBridgeError.duplicateTool")
    } catch HubBridgeError.duplicateTool(let name) {
      #expect(name == "weather")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func `FastMCP.Builder.addTools surfaces duplicateTool through the builder chain`() throws {
    // Same-batch collision.
    #expect(throws: HubBridgeError.self) {
      _ = try FastMCP.builder().addTools([WeatherTool(), WeatherTool()])
    }

    // Cross-call collision.
    let seeded = try FastMCP.builder().addTools([WeatherTool()])
    do {
      _ = try seeded.addTools([WeatherTool()])
      Issue.record("Expected HubBridgeError.duplicateTool")
    } catch HubBridgeError.duplicateTool(let name) {
      #expect(name == "weather")
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func `HubToolAdapter rejects native and proxied tool-name collision`() async throws {
    let adapter = try HubToolAdapter(tools: [WeatherTool()])
    let proxiedWeather = ProxiedMCPTool(
      serverName: "remote",
      originalName: "weather",
      tool: MCP.Tool(
        name: "weather",
        description: "Remote weather",
        inputSchema: .object(["type": .string("object")])
      )
    ) { _, _ in CallTool.Result() }

    await #expect(throws: HubBridgeError.self) {
      try await adapter.register(proxiedWeather)
    }
  }
}
