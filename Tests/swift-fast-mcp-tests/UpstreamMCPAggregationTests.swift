import ExampleTools
import FastMCPAIBridge
import Foundation
import Logging
import MCP
import Testing

@testable import FastMCP

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("Upstream MCP Aggregation")
struct UpstreamMCPAggregationTests {

  @Test
  func `builder stores streamable HTTP upstream configuration`() {
    let endpoint = URL(string: "https://example.com/mcp")!
    let builder = FastMCP.builder().addUpstreamMCPServer(
      name: "docs",
      transport: .streamableHTTP(
        endpoint: endpoint,
        headers: ["Authorization": "Bearer token"],
        streaming: false
      ),
      toolNamePrefix: "docs_"
    )

    #expect(builder.upstreamMCPServers.count == 1)
    let upstream = builder.upstreamMCPServers[0]
    #expect(upstream.name == "docs")
    #expect(upstream.toolNamePrefix == "docs_")

    guard case .streamableHTTP(let storedEndpoint, let headers, let streaming) = upstream.transport
    else {
      Issue.record("Expected streamableHTTP transport")
      return
    }

    #expect(storedEndpoint == endpoint)
    #expect(headers["Authorization"] == "Bearer token")
    #expect(streaming == false)
  }

  @Test
  func `proxied MCP tool lists with visible name and preserves metadata`() async throws {
    let adapter = HubToolAdapter()
    let inputSchema: Value = .object([
      "type": .string("object"),
      "properties": .object(["query": .object(["type": .string("string")])]),
      "required": .array([.string("query")]),
    ])
    let outputSchema: Value = .object([
      "type": .string("object"),
      "properties": .object(["answer": .object(["type": .string("string")])]),
    ])
    let upstreamTool = MCP.Tool(
      name: "docs_search",
      title: "Docs Search",
      description: "Search documentation",
      inputSchema: inputSchema,
      annotations: .init(readOnlyHint: true, openWorldHint: false),
      outputSchema: outputSchema,
      icons: [Icon(src: "https://example.com/icon.png")],
      _meta: Metadata(additionalFields: ["source": .string("upstream")])
    )

    try await adapter.register(
      ProxiedMCPTool(
        serverName: "docs",
        originalName: "search",
        tool: upstreamTool
      ) { _, _ in
        CallTool.Result(content: [.text(text: "ok", annotations: nil, _meta: nil)])
      }
    )

    let listedTools = await adapter.listTools()
    #expect(listedTools.count == 1)
    let listed = try #require(listedTools.first)
    #expect(listed.name == "docs_search")
    #expect(listed.title == "Docs Search")
    #expect(listed.description == "Search documentation")
    #expect(listed.inputSchema == inputSchema)
    #expect(listed.outputSchema == outputSchema)
    #expect(listed.annotations.readOnlyHint == true)
    #expect(listed.annotations.openWorldHint == false)
    #expect(listed.icons?.first?.src == "https://example.com/icon.png")
    #expect(listed._meta?["source"] == .string("upstream"))
  }

  @Test
  func `proxied MCP tool forwards arguments and structured content`() async throws {
    let adapter = HubToolAdapter()
    let upstreamTool = MCP.Tool(
      name: "c4ai_md",
      description: "Fetch markdown",
      inputSchema: .object(["type": .string("object")])
    )
    final class Recorder: @unchecked Sendable {
      var arguments: [String: Value]?
      var meta: Metadata?
    }
    let recorder = Recorder()

    try await adapter.register(
      ProxiedMCPTool(
        serverName: "c4ai",
        originalName: "md",
        tool: upstreamTool
      ) { arguments, meta in
        recorder.arguments = arguments
        recorder.meta = meta
        return CallTool.Result(
          content: [.text(text: "markdown", annotations: nil, _meta: nil)],
          structuredContent: .object(["markdown": .string("# Title")]),
          isError: false,
          _meta: Metadata(additionalFields: ["upstream": .string("c4ai")])
        )
      }
    )

    let expectedContent: [MCP.Tool.Content] = [
      .text(text: "markdown", annotations: nil, _meta: nil)
    ]
    let expectedStructuredContent: Value = .object(["markdown": .string("# Title")])
    let result = try await adapter.callTool(
      name: "c4ai_md",
      arguments: .object(["url": .string("https://example.com")]),
      meta: Metadata(progressToken: .string("token-1"))
    )

    #expect(recorder.arguments?["url"] == .string("https://example.com"))
    #expect(recorder.meta?["progressToken"] == .string("token-1"))
    #expect(result.content == expectedContent)
    #expect(result.structuredContent == expectedStructuredContent)
    #expect(result.isError == false)
    #expect(result._meta?["upstream"] == .string("c4ai"))
  }

  @Test
  func `replace proxied tools is atomic on duplicate names`() async throws {
    let adapter = HubToolAdapter()
    let first = ProxiedMCPTool(
      serverName: "first",
      originalName: "search",
      tool: MCP.Tool(
        name: "search",
        description: "First search",
        inputSchema: .object(["type": .string("object")])
      )
    ) { _, _ in CallTool.Result() }
    try await adapter.register(first)

    let duplicate = ProxiedMCPTool(
      serverName: "second",
      originalName: "search",
      tool: MCP.Tool(
        name: "search",
        description: "Second search",
        inputSchema: .object(["type": .string("object")])
      )
    ) { _, _ in CallTool.Result() }

    await #expect(throws: HubBridgeError.self) {
      try await adapter.replaceProxiedTools(serverName: "second", with: [duplicate])
    }

    let names = await adapter.names()
    #expect(names == ["search"])
    let listed = await adapter.listTools()
    #expect(listed.first?.description == "First search")
  }

  @Test
  func `manager discovers and forwards through local streamable HTTP upstream`() async throws {
    let port = Int.random(in: 18_000...28_000)
    let upstreamHTTPServer = FastMCPHTTPServer(
      configuration: .init(host: "127.0.0.1", port: port, endpoint: "/mcp"),
      statelessServerFactory: { transport in
        let server = Server(
          name: "upstream",
          version: "1.0.0",
          capabilities: .init(tools: .init())
        )
        await server.register(hubTools: try HubToolAdapter(tools: [MathTool()]))
        try await server.start(transport: transport)
        return server
      },
      logger: Logger(label: "test.upstream")
    )

    let serverTask = Task {
      try await upstreamHTTPServer.start()
    }
    defer {
      serverTask.cancel()
      Task { await upstreamHTTPServer.stop() }
    }

    try await waitForHTTPServer(port: port, endpoint: "/mcp")

    let adapter = HubToolAdapter()
    let manager = UpstreamMCPManager(toolAdapter: adapter, logger: Logger(label: "test.manager"))
    try await manager.addServer(
      UpstreamMCPServerConfiguration(
        name: "upstream",
        transport: .streamableHTTP(
          endpoint: URL(string: "http://127.0.0.1:\(port)/mcp")!,
          streaming: false
        ),
        toolNamePrefix: "up_"
      )
    )
    defer {
      Task { await manager.disconnectAll() }
    }

    let tools = await adapter.listTools()
    #expect(tools.map(\.name) == ["up_math"])

    let result = try await adapter.callTool(
      name: "up_math",
      arguments: .object([
        "operation": .string("add"),
        "a": .double(2),
        "b": .double(3),
      ]),
      meta: nil
    )
    #expect(result.content == [.text(text: "\"Result: 5.0\"", annotations: nil, _meta: nil)])
  }
}

private func waitForHTTPServer(port: Int, endpoint: String) async throws {
  let url = URL(string: "http://127.0.0.1:\(port)\(endpoint)")!
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = Data("{}".utf8)

  for _ in 0..<50 {
    do {
      _ = try await URLSession.shared.data(for: request)
      return
    } catch {
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  throw FastMCPError.serverStartFailed("Timed out waiting for upstream test server")
}
