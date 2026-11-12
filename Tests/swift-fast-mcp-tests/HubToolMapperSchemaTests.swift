import ExampleTools
import FastMCPAIBridge
import SwiftAIHub
import Testing

// Selective MCP imports — full `import MCP` makes @Generable's `Prompt`
// ambiguous against `MCP.Prompt`.
import enum MCP.Value

@Suite("HubToolMapper Schema Tests")
struct HubToolMapperSchemaTests {

  @Test
  func `WeatherTool input schema projects nested Arguments struct`() {
    let mapped = HubToolMapper.mapTool(WeatherTool())

    guard case .object(let root) = mapped.inputSchema else {
      Issue.record("Expected object root schema")
      return
    }
    #expect(root["type"] == .string("object"))

    guard case .object(let properties) = root["properties"] ?? .null else {
      Issue.record("Expected properties object")
      return
    }

    guard case .object(let coordinate) = properties["coordinate"] ?? .null else {
      Issue.record("Expected coordinate object schema")
      return
    }
    #expect(coordinate["type"] == .string("object"))
    guard case .object(let coordProps) = coordinate["properties"] ?? .null else {
      Issue.record("Expected coordinate.properties")
      return
    }
    #expect((coordProps["latitude"]?.objectValue?["type"]) == .string("number"))
    #expect((coordProps["longitude"]?.objectValue?["type"]) == .string("number"))

    guard case .object(let unit) = properties["unit"] ?? .null else {
      Issue.record("Expected unit object schema")
      return
    }
    #expect(unit["type"] == .string("string"))
    #expect(unit["enum"] == .array([.string("celsius"), .string("fahrenheit")]))

    guard case .array(let required) = root["required"] ?? .null else {
      Issue.record("Expected required array")
      return
    }
    #expect(required.contains(.string("coordinate")))
    #expect(required.contains(.string("unit")))
  }

  @Test
  func `StructuredSearchTool outputSchema is object with summary and resultCount`() {
    let mapped = HubToolMapper.mapTool(StructuredSearchTool())
    let schema = HubToolMapper.outputSchema(for: StructuredSearchTool())

    // mapTool wires the same projection; compare by shape (GenerationSchema
    // `required` key order can vary between encodings).
    #expect(mapped.outputSchema != nil)
    #expect(schema != nil)

    guard case .object(let root) = schema else {
      Issue.record("Expected object outputSchema, got \(String(describing: schema))")
      return
    }
    #expect(root["type"] == .string("object"))
    guard case .object(let properties) = root["properties"] ?? .null else {
      Issue.record("Expected properties object")
      return
    }
    #expect(properties["summary"] != nil)
    #expect(properties["resultCount"] != nil)

    guard case .object(let mappedRoot) = mapped.outputSchema else {
      Issue.record("Expected mapTool to pass outputSchema")
      return
    }
    #expect(mappedRoot["type"] == .string("object"))
    guard case .object(let mappedProps) = mappedRoot["properties"] ?? .null else {
      Issue.record("Expected mapped properties")
      return
    }
    #expect(mappedProps["summary"] != nil)
    #expect(mappedProps["resultCount"] != nil)
  }

  @Test
  func `String and array tool outputs have nil outputSchema`() {
    #expect(HubToolMapper.outputSchema(for: MathTool()) == nil)
    #expect(HubToolMapper.mapTool(MathTool()).outputSchema == nil)

    #expect(HubToolMapper.outputSchema(for: ArrayEchoTool()) == nil)
    #expect(HubToolMapper.mapTool(ArrayEchoTool()).outputSchema == nil)

    // Documented non-object Generable outputs also yield nil.
    #expect(HubToolMapper.outputSchema(for: GeneratedContentEchoTool()) == nil)
  }
}

// MARK: - Fixture tools for outputSchema coverage

private struct ArrayEchoTool: SwiftAIHub.Tool {
  let name = "arrayEcho"
  let description = "Returns a fixed string array."

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> [String] {
    ["one", "two"]
  }
}

private struct GeneratedContentEchoTool: SwiftAIHub.Tool {
  let name = "generatedContentEcho"
  let description = "Returns free-form GeneratedContent."

  @Generable
  struct Arguments {}

  func call(arguments: Arguments) async throws -> GeneratedContent {
    GeneratedContent(kind: .string("dynamic"))
  }
}
