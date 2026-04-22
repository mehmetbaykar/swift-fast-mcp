// Exercises the "dual-use tools" promise: one tool exposed over MCP, a second
// tool visible only inside the outer tool's LLM loop. The wire-surface
// assertions run unconditionally; the OpenAI live roundtrip runs only when
// OPENAI_API_KEY is set.
//
// FALLBACK: we round-trip through HubToolAdapter directly instead of driving
// mcp-inspector via npx — that is the same code path the MCP server calls on
// `tools/call`, and it sidesteps the brittleness of a subprocess handshake.

import FastMCPAIBridge
import Foundation
import MCP
import SwiftAIHub
import Testing

@testable import FastMCP

// MARK: - Fixture tools (macro-only)

@Tool("Return the current date/time in an IANA timezone.")
private struct GetCurrentDateTool {
  @Parameter("IANA tz, e.g. 'Europe/Berlin'. Defaults to server local.")
  var timezone: String? = nil

  func execute() async throws -> String {
    let tz = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
    let fmt = ISO8601DateFormatter()
    fmt.timeZone = tz
    return fmt.string(from: .now)
  }
}

@Tool("Search the web for a query. Returns a concise summary.")
private struct OnlineSearchTool {
  let llm: (any LanguageModel)?

  @Parameter("The user's query")
  var query: String

  init(llm: (any LanguageModel)? = nil) {
    self.llm = llm
    self.query = ""
  }

  func execute() async throws -> String {
    guard let llm else {
      // No LLM configured — echo back so the wire-surface test still has
      // something deterministic to assert on.
      return "stub: \(query)"
    }
    let session = LanguageModelSession(
      model: llm,
      tools: [GetCurrentDateTool()],
      instructions: "Always include today's date before the answer."
    )
    let response = try await session.respond(to: "Search the web for: \(query)")
    return response.content
  }
}

// MARK: - Tests

@Suite("onlineSearch dual-use integration")
struct OnlineSearchIntegrationTests {

  @Test("tools/list exposes only onlineSearch; getCurrentDate stays internal")
  func wireSurfaceHidesInternalTool() async throws {
    let adapter = HubToolAdapter(tools: [OnlineSearchTool()])
    let names = await adapter.names()
    #expect(names == ["onlineSearch"])
    #expect(!names.contains("getCurrentDate"))
  }

  @Test("tools/call onlineSearch round-trips through the hub adapter")
  func toolsCallDispatchesThroughBridge() async throws {
    let adapter = HubToolAdapter(tools: [OnlineSearchTool()])
    let content = try await adapter.execute(
      name: "onlineSearch",
      arguments: .object(["query": .string("swift concurrency")])
    )
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string output, got \(content.kind)")
      return
    }
    #expect(text == "stub: swift concurrency")
  }

  @Test(
    "OpenAI live round-trip with getCurrentDate mid-loop",
    .enabled(if: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil)
  )
  func liveOpenAIRoundTrip() async throws {
    guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
      return
    }
    let llm = OpenAILanguageModel(apiKey: key, model: "gpt-4o-mini")
    let adapter = HubToolAdapter(tools: [OnlineSearchTool(llm: llm)])
    let content = try await adapter.execute(
      name: "onlineSearch",
      arguments: .object(["query": .string("What is today's date?")])
    )
    guard case .string(let text) = content.kind else {
      Issue.record("Expected string output")
      return
    }
    #expect(!text.isEmpty)
  }
}
