import Testing

@testable import FastMCP

// Sample prompt exercising the default name-derivation rule (strip `Prompt`,
// lowercase first char). Verifies the `@MCPPrompt` macro synthesises all
// required protocol members and dispatches string arguments onto typed
// properties before invoking the user's zero-arg `getMessages()`.
@MCPPrompt("Sample prompt used by macro tests")
struct SamplePrompt {
  @PromptArgument("Who to greet")
  var who: String

  @PromptArgument("Use formal tone")
  var formal: Bool?

  func getMessages() async throws -> Messages {
    let suffix = formal == true ? "formally" : "casually"
    return [.user("Hi \(who) \(suffix)")]
  }
}

// Verifies explicit `name:` override on the attribute wins over derivation.
@MCPPrompt("Override-name prompt", name: "custom_name")
struct NamedPrompt {
  func getMessages() async throws -> Messages {
    [.user("hello")]
  }
}

// Verifies numeric argument coercion from the raw `[String: String]` payload.
@MCPPrompt("Numeric coercion prompt")
struct NumericPrompt {
  @PromptArgument("Count")
  var count: Int

  @PromptArgument("Ratio")
  var ratio: Double?

  func getMessages() async throws -> Messages {
    [.user("count=\(count) ratio=\(ratio.map { String($0) } ?? "nil")")]
  }
}

@Suite("MCPPrompt macro")
struct MCPPromptMacroTests {

  @Test
  func derivedNameStripsPromptSuffixAndLowercasesFirst() {
    #expect(SamplePrompt().name == "sample")
  }

  @Test
  func descriptionIsPopulatedFromAttribute() {
    #expect(SamplePrompt().description == "Sample prompt used by macro tests")
  }

  @Test
  func argumentsArrayReflectsPropertyAnnotations() {
    let args = SamplePrompt().arguments
    #expect(args.count == 2)
    #expect(args[0].name == "who")
    #expect(args[0].required == true)
    #expect(args[0].description == "Who to greet")
    #expect(args[1].name == "formal")
    #expect(args[1].required == false)
  }

  @Test
  func dispatchAssignsStringArgumentsAndCallsZeroArgGetMessages() async throws {
    let messages = try await SamplePrompt().getMessages(
      arguments: ["who": "world", "formal": "true"]
    )
    #expect(messages.count == 1)
    guard case .text(let body) = messages[0].content else {
      Issue.record("expected text content")
      return
    }
    #expect(body == "Hi world formally")
  }

  @Test
  func explicitNameOverridesDerivation() {
    #expect(NamedPrompt().name == "custom_name")
  }

  @Test
  func numericArgumentCoercion() async throws {
    let messages = try await NumericPrompt().getMessages(
      arguments: ["count": "42", "ratio": "1.5"]
    )
    guard case .text(let body) = messages[0].content else {
      Issue.record("expected text content")
      return
    }
    #expect(body == "count=42 ratio=1.5")
  }
}

// MARK: - @MCPResource

@MCPResource(
  "test://sample",
  name: "Sample",
  description: "Sample resource used by macro tests",
  mimeType: .textPlain
)
struct SampleResource {
  @ResourceContentBuilder
  var content: Content {
    "hello world"
  }
}

@Suite("MCPResource macro")
struct MCPResourceMacroTests {

  @Test
  func uriIsPopulated() {
    #expect(SampleResource().uri == "test://sample")
  }

  @Test
  func nameDescriptionMimeTypeAreSynthesised() {
    let r = SampleResource()
    #expect(r.name == "Sample")
    #expect(r.description == "Sample resource used by macro tests")
    #expect(r.mimeType == "text/plain")
  }

  @Test
  func contentBodyIsPreserved() async throws {
    let items = try await SampleResource().content
    #expect(items.count == 1)
    guard case .text(let text) = items[0].content else {
      Issue.record("expected text content")
      return
    }
    #expect(text == "hello world")
  }
}
