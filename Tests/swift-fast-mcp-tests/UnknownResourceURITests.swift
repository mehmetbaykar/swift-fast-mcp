import FastMCP
import MCP
import Testing

@MCPResource("test://known", name: "Known")
private struct KnownResource {
  @ResourceContentBuilder
  var content: Content {
    "known"
  }
}

@Suite("Unknown resource URI error")
struct UnknownResourceURITests {

  @Test func `resources read unknown URI is invalid params`() async throws {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

    let server = Server(
      name: "UnknownURIServer",
      version: "1.0.0",
      capabilities: .init(resources: .init())
    )
    await server.register(resources: [KnownResource()])

    let client = Client(name: "UnknownURIClient", version: "1.0.0")
    try await server.start(transport: serverTransport)
    try await client.connect(transport: clientTransport)

    do {
      _ = try await client.readResource(uri: "test://missing")
      Issue.record("expected readResource to throw for unknown URI")
    } catch let error as MCPError {
      #expect(error == .invalidParams("Unknown resource URI: test://missing"))
      #expect(error.code == -32602)
    } catch {
      Issue.record("expected MCPError, got \(error)")
    }

    await server.stop()
    await client.disconnect()
  }
}
