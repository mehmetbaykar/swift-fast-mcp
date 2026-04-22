// Exercises the "dual-use tools" promise from docs/05-tools-dual-use.md:
// - Test A (behaviour): OnlineSearchTool.execute() runs end-to-end against a
//   live LLM, internally spinning up a LanguageModelSession with
//   GetCurrentDateTool as an internal-only tool. Skipped unless
//   OPENAI_API_KEY is set.
// - Test B (wire surface): when registered with the FastMCP adapter, only
//   `onlineSearch` is externally visible; `getCurrentDate` stays internal.
//
// Neither test goes through `HubToolAdapter.execute(name:arguments:)` — that
// is the MCP wire dispatch path, not application API. We call the tool
// directly via typed property access (Test A) and use the adapter's
// in-memory `names()` introspection (Test B).

import FastMCPAIBridge
import Foundation
import SwiftAIHub
import Testing

@testable import FastMCP

// MARK: - Fixture tools (macro-driven, typed @Parameter access)

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
  // DI — ignored by the macro, injected at construction.
  let llm: any LanguageModel

  @Parameter("The user's query")
  var query: String

  init(llm: any LanguageModel, query: String = "") {
    self.llm = llm
    self.query = query
  }

  func execute() async throws -> String {
    let session = LanguageModelSession(
      model: llm,
      tools: [GetCurrentDateTool()],
      instructions: "Always include today's date before the answer."
    )
    let response = try await session.respond(to: "Search the web for: \(query)")
    return response.content
  }
}

// MARK: - Inline mock language model (Test B)
//
// Mirrors the 20-LoC shape of AnyLanguageModel/.../Shared/MockLanguageModel.swift
// but against swift-ai-hub's LanguageModel protocol. The wire-surface test
// never invokes execute(), so the body is a stub.

private struct StubLanguageModel: LanguageModel {
  typealias UnavailableReason = Never

  func respond<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions
  ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
    guard type == String.self else {
      fatalError("StubLanguageModel only supports String")
    }
    let text = "stub"
    return LanguageModelSession.Response(
      content: text as! Content,
      rawContent: GeneratedContent(text),
      transcriptEntries: []
    )
  }

  func streamResponse<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions
  ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
    LanguageModelSession.ResponseStream(
      content: "stub" as! Content,
      rawContent: GeneratedContent("stub")
    )
  }
}

// MARK: - Tests

@Suite("onlineSearch dual-use integration")
struct OnlineSearchIntegrationTests {

  // Test B — wire visibility. Asserts the MCP surface exposes `onlineSearch`
  // and keeps `getCurrentDate` out of `tools/list`. Runs on every CI.
  @Test("MCP tools/list exposes only onlineSearch; getCurrentDate stays internal")
  func onlineSearchIsTheOnlyMCPExposedTool() async throws {
    let adapter = HubToolAdapter(tools: [OnlineSearchTool(llm: StubLanguageModel())])
    let names = await adapter.names()

    #expect(names == ["onlineSearch"])
    #expect(!names.contains("getCurrentDate"))
  }

  // Test A — behaviour. Types `tool.query` at compile time, calls
  // `tool.execute()` directly. Skipped cleanly when the env var is unset.
  @Test(
    "OnlineSearchTool.execute runs a live OpenAI loop and returns a non-empty response",
    .enabled(if: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.isEmpty == false)
  )
  func onlineSearchToolProducesResponseWithDate() async throws {
    let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    let openAI = OpenAILanguageModel(apiKey: key, model: "gpt-4o-mini")

    var tool = OnlineSearchTool(llm: openAI)
    tool.query = "What is today's date?"
    let response = try await tool.execute()

    #expect(!response.isEmpty, "tool returned empty response")
  }
}
