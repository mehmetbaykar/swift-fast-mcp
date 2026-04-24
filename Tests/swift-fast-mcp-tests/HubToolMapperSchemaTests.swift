import ExampleTools
import FastMCPAIBridge
import MCP
import Testing

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
}
