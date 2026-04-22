// Exercises the "dual-use tools" promise from docs/05-tools-dual-use.md:
// - Test A (behaviour): OnlineSearchTool.execute() runs end-to-end against the
//   real OpenAILanguageModel provider with a mocked HTTP transport. The test
//   drives two scripted HTTP responses — first a tool-call for
//   `getCurrentDate`, then a final assistant message — exercising the
//   provider's request building, JSON decode, tool-call loop, and tool-output
//   posting. Deterministic; no network; runs on Linux CI without any key.
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

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

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

// MARK: - Stub LanguageModel (Test B only, never invoked)

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

// MARK: - MockURLProtocol: deterministic in-process HTTP backend
//
// Scripts a sequence of responses keyed by (path + optional body substring).
// Works on Apple URLSession and Linux FoundationNetworking URLSession because
// both respect `URLSessionConfiguration.protocolClasses` for per-session
// (non-`shared`) sessions. Each script entry is consumed in FIFO order among
// entries whose matcher accepts the request, letting the test route round-1
// vs round-2 by body substring.

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  struct Match {
    let pathSuffix: String
    let bodyContains: String?
    let status: Int
    let body: Data
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var script: [Match] = []
  nonisolated(unsafe) private static var consumed: [Match] = []

  static func install(script: [Match]) -> URLSession {
    lock.lock()
    self.script = script
    self.consumed = []
    lock.unlock()

    let config = URLSessionConfiguration.default
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }

  static func consumedCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return consumed.count
  }

  static func remainingCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return script.count
  }

  private static func popMatch(for request: URLRequest, bodyString: String) -> Match? {
    lock.lock()
    defer { lock.unlock() }
    let path = request.url?.path ?? ""
    for (index, candidate) in script.enumerated() {
      guard path.hasSuffix(candidate.pathSuffix) else { continue }
      if let needle = candidate.bodyContains, !bodyString.contains(needle) { continue }
      let match = script.remove(at: index)
      consumed.append(match)
      return match
    }
    return nil
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    // Linux FoundationNetworking strips httpBody from the delivered URLRequest
    // and exposes the payload via httpBodyStream. Read both paths.
    let bodyData: Data = {
      if let data = request.httpBody { return data }
      if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
          let read = stream.read(buf, maxLength: 4096)
          if read <= 0 { break }
          data.append(buf, count: read)
        }
        return data
      }
      return Data()
    }()
    let bodyString = String(data: bodyData, encoding: .utf8) ?? ""

    guard let match = MockURLProtocol.popMatch(for: request, bodyString: bodyString) else {
      let error = NSError(
        domain: "MockURLProtocol",
        code: 404,
        userInfo: [
          NSLocalizedDescriptionKey:
            "No scripted response for request \(request.url?.absoluteString ?? "?") body=\(bodyString.prefix(200))"
        ]
      )
      client?.urlProtocol(self, didFailWithError: error)
      return
    }

    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: match.status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: match.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
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

  // Test A — behaviour. Drives OnlineSearchTool.execute() against the real
  // OpenAILanguageModel provider backed by MockURLProtocol. Two scripted
  // responses: round 1 emits a tool_call for getCurrentDate; round 2 emits
  // the final assistant message (containing 2026). Exercises request build,
  // JSON decode, tool-call loop, and tool-output posting end-to-end.
  @Test("OnlineSearchTool.execute runs tool-call loop against mocked OpenAI backend")
  func onlineSearchToolRunsToolCallLoopAgainstMockedBackend() async throws {
    let firstRoundJSON = """
      {
        "id": "chatcmpl-mock1",
        "object": "chat.completion",
        "created": 1777000000,
        "model": "gpt-4o-mini",
        "choices": [{
          "index": 0,
          "message": {
            "role": "assistant",
            "content": null,
            "tool_calls": [{
              "id": "call_mock_date",
              "type": "function",
              "function": {
                "name": "getCurrentDate",
                "arguments": "{\\"timezone\\":\\"UTC\\"}"
              }
            }]
          },
          "finish_reason": "tool_calls"
        }]
      }
      """.data(using: .utf8)!

    let secondRoundJSON = """
      {
        "id": "chatcmpl-mock2",
        "object": "chat.completion",
        "created": 1777000001,
        "model": "gpt-4o-mini",
        "choices": [{
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "Today is 2026-04-22. Swift concurrency continues to evolve with typed throws, region-based isolation, and new actor ergonomics."
          },
          "finish_reason": "stop"
        }]
      }
      """.data(using: .utf8)!

    // Round 1 matches any first POST to /chat/completions (the user message is
    // always present; use it to disambiguate). Round 2 is matched by the
    // presence of the tool-call id echoed back in the tool-output message.
    let mockSession = MockURLProtocol.install(script: [
      .init(
        pathSuffix: "/chat/completions",
        bodyContains: "Search the web for:",
        status: 200,
        body: firstRoundJSON
      ),
      .init(
        pathSuffix: "/chat/completions",
        bodyContains: "call_mock_date",
        status: 200,
        body: secondRoundJSON
      ),
    ])

    let openAI = OpenAILanguageModel(
      baseURL: URL(string: "https://mock.openai.test/v1/")!,
      apiKey: "mock-key",
      model: "gpt-4o-mini",
      session: mockSession
    )

    var tool = OnlineSearchTool(llm: openAI)
    tool.query = "swift concurrency"
    let response = try await tool.execute()

    #expect(!response.isEmpty, "tool returned empty response")
    #expect(response.contains("2026"), "final response should echo mocked date: \(response)")
    #expect(
      MockURLProtocol.remainingCount() == 0,
      "unconsumed scripted responses: \(MockURLProtocol.remainingCount())"
    )
    #expect(
      MockURLProtocol.consumedCount() == 2,
      "expected 2 HTTP round-trips, saw \(MockURLProtocol.consumedCount())"
    )
  }
}
