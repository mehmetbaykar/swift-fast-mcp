import ExampleTools
import MCPToolkit
import Testing

@testable import FastMCP

@Suite("Tool Deduplicator Tests")
struct ToolDeduplicatorTests {

  let deduplicator = ToolDeduplicator()

  @Test
  func emptyInputsReturnEmptyResult() {
    let result = deduplicator.deduplicate([], adding: [])
    #expect(result.isEmpty)
  }

  @Test
  func existingToolsArePreserved() {
    let existing: [any MCPTool] = [WeatherTool(), MathTool()]
    let result = deduplicator.deduplicate(existing, adding: [])
    #expect(result.count == 2)
  }

  @Test
  func newToolsAreAddedToEmpty() {
    let newTools: [any MCPTool] = [WeatherTool(), MathTool()]
    let result = deduplicator.deduplicate([], adding: newTools)
    #expect(result.count == 2)
  }

  @Test
  func uniqueToolsAreCombined() {
    let existing: [any MCPTool] = [WeatherTool()]
    let newTools: [any MCPTool] = [MathTool()]
    let result = deduplicator.deduplicate(existing, adding: newTools)
    #expect(result.count == 2)

    let toolNames = result.map { $0.name }
    #expect(toolNames.contains("get_weather"))
    #expect(toolNames.contains("calculate"))
  }

  @Test
  func duplicateToolsAreFiltered() {
    let existing: [any MCPTool] = [WeatherTool()]
    let newTools: [any MCPTool] = [WeatherTool(), MathTool()]
    let result = deduplicator.deduplicate(existing, adding: newTools)
    #expect(result.count == 2)
  }

  @Test
  func orderIsPreserved() {
    let existing: [any MCPTool] = [WeatherTool()]
    let newTools: [any MCPTool] = [GreetingTool(), MathTool()]
    let result = deduplicator.deduplicate(existing, adding: newTools)

    #expect(result[0].name == "get_weather")
    #expect(result[1].name == "greet")
    #expect(result[2].name == "calculate")
  }

  @Test
  func allDuplicatesFilteredWhenAllMatch() {
    let existing: [any MCPTool] = [WeatherTool(), MathTool(), GreetingTool()]
    let newTools: [any MCPTool] = [WeatherTool(), MathTool(), GreetingTool()]
    let result = deduplicator.deduplicate(existing, adding: newTools)
    #expect(result.count == 3)
  }
}

struct MockResource: MCPResource {
  let uri: String
  let name: String
  let description: String? = nil
  let mimeType: String? = nil

  var content: Content {
    "mock content"
  }
}

@Suite("Prompt Deduplicator Tests")
struct PromptDeduplicatorTests {

  let deduplicator = PromptDeduplicator()

  @Test
  func emptyInputsReturnEmptyResult() {
    let result = deduplicator.deduplicate([], adding: [])
    #expect(result.isEmpty)
  }

  @Test
  func existingPromptsArePreserved() {
    let existing: [any MCPPrompt] = [GreetingPrompt()]
    let result = deduplicator.deduplicate(existing, adding: [])
    #expect(result.count == 1)
  }

  @Test
  func newPromptsAreAddedToEmpty() {
    let newPrompts: [any MCPPrompt] = [GreetingPrompt()]
    let result = deduplicator.deduplicate([], adding: newPrompts)
    #expect(result.count == 1)
  }

  @Test
  func duplicatePromptsAreFilteredByName() {
    let existing: [any MCPPrompt] = [GreetingPrompt()]
    let newPrompts: [any MCPPrompt] = [GreetingPrompt()]
    let result = deduplicator.deduplicate(existing, adding: newPrompts)
    #expect(result.count == 1)
  }
}

@Suite("Resource Deduplicator Tests")
struct ResourceDeduplicatorTests {

  let deduplicator = ResourceDeduplicator()

  @Test
  func emptyInputsReturnEmptyResult() {
    let result = deduplicator.deduplicate([], adding: [])
    #expect(result.isEmpty)
  }

  @Test
  func existingResourcesArePreserved() {
    let existing: [any MCPResource] = [
      MockResource(uri: "file://a.txt", name: "A"),
      MockResource(uri: "file://b.txt", name: "B"),
    ]
    let result = deduplicator.deduplicate(existing, adding: [])
    #expect(result.count == 2)
  }

  @Test
  func newResourcesAreAddedToEmpty() {
    let newResources: [any MCPResource] = [
      MockResource(uri: "file://a.txt", name: "A"),
      MockResource(uri: "file://b.txt", name: "B"),
    ]
    let result = deduplicator.deduplicate([], adding: newResources)
    #expect(result.count == 2)
  }

  @Test
  func uniqueResourcesAreCombined() {
    let existing: [any MCPResource] = [MockResource(uri: "file://a.txt", name: "A")]
    let newResources: [any MCPResource] = [MockResource(uri: "file://b.txt", name: "B")]
    let result = deduplicator.deduplicate(existing, adding: newResources)
    #expect(result.count == 2)

    let uris = result.map { $0.uri }
    #expect(uris.contains("file://a.txt"))
    #expect(uris.contains("file://b.txt"))
  }

  @Test
  func duplicateResourcesAreFilteredByURI() {
    let existing: [any MCPResource] = [MockResource(uri: "file://a.txt", name: "A")]
    let newResources: [any MCPResource] = [
      MockResource(uri: "file://a.txt", name: "Different Name"),
      MockResource(uri: "file://b.txt", name: "B"),
    ]
    let result = deduplicator.deduplicate(existing, adding: newResources)
    #expect(result.count == 2)
  }

  @Test
  func orderIsPreserved() {
    let existing: [any MCPResource] = [MockResource(uri: "file://a.txt", name: "A")]
    let newResources: [any MCPResource] = [
      MockResource(uri: "file://c.txt", name: "C"),
      MockResource(uri: "file://b.txt", name: "B"),
    ]
    let result = deduplicator.deduplicate(existing, adding: newResources)

    #expect(result[0].uri == "file://a.txt")
    #expect(result[1].uri == "file://c.txt")
    #expect(result[2].uri == "file://b.txt")
  }
}
