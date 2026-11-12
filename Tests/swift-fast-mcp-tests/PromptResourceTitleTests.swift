import FastMCP
import MCP
import Testing

// MARK: - Fixtures

@MCPPrompt("Titled prompt", title: "Friendly Greeting")
private struct TitledPrompt {
  func getMessages() async throws -> Messages {
    [.user("hello")]
  }
}

@MCPPrompt("Untitled prompt")
private struct UntitledPrompt {
  func getMessages() async throws -> Messages {
    [.user("hello")]
  }
}

@MCPResource(
  "test://titled",
  name: "Titled",
  title: "Config Display",
  description: "A titled resource",
  mimeType: .textPlain
)
private struct TitledResource {
  @ResourceContentBuilder
  var content: Content {
    "titled"
  }
}

@MCPResource("test://untitled", name: "Untitled")
private struct UntitledResource {
  @ResourceContentBuilder
  var content: Content {
    "untitled"
  }
}

/// Hand-written MCPPrompt conformance that supplies an explicit title.
private struct HandWrittenTitledPrompt: MCPPrompt {
  var name: String { "hand_prompt" }
  var title: String? { "Hand Title" }
  var description: String? { "hand-written" }
  var arguments: [PromptArgumentSpec] { [] }

  func getMessages(arguments: [String: String]) async throws -> Messages {
    [.user("hand")]
  }
}

/// Hand-written MCPResource conformance that supplies an explicit title.
private struct HandWrittenTitledResource: MCPResource {
  var uri: String { "test://hand" }
  var name: String? { "Hand" }
  var title: String? { "Hand Resource Title" }
  var description: String? { "hand-written resource" }
  var mimeType: String? { "text/plain" }

  @ResourceContentBuilder
  var content: Content {
    "hand"
  }
}

/// Property named `title` without macro `title:` — must keep compiling.
@MCPPrompt("Prompt with a title argument property")
private struct TitleArgumentPrompt {
  @PromptArgument("The document title", name: "title")
  var title: String

  func getMessages() async throws -> Messages {
    [.user("Title is \(title)")]
  }
}

@Suite("Prompt and resource title")
struct PromptResourceTitleTests {

  @Test func `macro title appears in toPrompt`() {
    let prompt = TitledPrompt().toPrompt()
    #expect(prompt.title == "Friendly Greeting")
    #expect(prompt.name == "titled")
  }

  @Test func `macro without title leaves toPrompt title nil`() {
    #expect(UntitledPrompt().toPrompt().title == nil)
  }

  @Test func `macro title appears in toResource`() {
    let resource = TitledResource().toResource()
    #expect(resource.title == "Config Display")
    #expect(resource.uri == "test://titled")
  }

  @Test func `macro without title leaves toResource title nil`() {
    #expect(UntitledResource().toResource().title == nil)
  }

  @Test func `hand written prompt title flows through toPrompt`() {
    #expect(HandWrittenTitledPrompt().toPrompt().title == "Hand Title")
  }

  @Test func `hand written resource title flows through toResource`() {
    #expect(HandWrittenTitledResource().toResource().title == "Hand Resource Title")
  }

  @Test func `property named title without macro title still works`() async throws {
    let prompt = TitleArgumentPrompt()
    #expect(prompt.toPrompt().title == nil)
    #expect(prompt.arguments.contains { $0.name == "title" })
    let messages = try await prompt.getMessages(arguments: ["title": "War and Peace"])
    guard case .text(let body) = messages[0].content else {
      Issue.record("expected text content")
      return
    }
    #expect(body == "Title is War and Peace")
  }

  @Test func `prompts list and resources list include title`() async throws {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

    let server = Server(
      name: "TitleListServer",
      version: "1.0.0",
      capabilities: .init(prompts: .init(), resources: .init())
    )
    await server.register(prompts: [TitledPrompt()])
    await server.register(resources: [TitledResource()])

    let client = Client(name: "TitleListClient", version: "1.0.0")
    try await server.start(transport: serverTransport)
    try await client.connect(transport: clientTransport)

    let (prompts, _) = try await client.listPrompts()
    #expect(prompts.count == 1)
    #expect(prompts[0].title == "Friendly Greeting")

    let (resources, _) = try await client.listResources()
    #expect(resources.count == 1)
    #expect(resources[0].title == "Config Display")

    await server.stop()
    await client.disconnect()
  }
}
