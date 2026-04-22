// swift-fast-mcp — FastMCPAIBridge
// Converts a SwiftAIHub.Tool into an MCP.Tool wire description.

import Foundation
import MCP
import SwiftAIHub

public enum HubToolMapper {
  public static func mapTool(_ tool: any SwiftAIHub.Tool) -> MCP.Tool {
    return MCP.Tool(
      name: tool.name,
      description: tool.description,
      inputSchema: inputSchema(for: tool)
    )
  }

  /// Projects the tool's `Arguments.generationSchema` (exposed on the `Tool`
  /// protocol via `parameters`) into a JSON Schema `Value` suitable for an
  /// MCP `tools/list` response.
  ///
  /// `GenerationSchema` keeps its node types internal but is publicly
  /// `Codable`, so we round-trip through JSON and then inline any
  /// `$defs` / `$ref` pairs — most MCP clients do not resolve JSON Schema
  /// references, so the returned schema is dereferenced.
  public static func inputSchema(for tool: any SwiftAIHub.Tool) -> Value {
    if let value = jsonSchemaValue(from: tool.parameters) {
      return value
    }
    // Fallback: free-form object if encoding fails unexpectedly.
    return .object([
      "type": .string("object"),
      "additionalProperties": .bool(true),
    ])
  }

  // MARK: - Conversion

  /// Encodes a `GenerationSchema` to JSON then decodes into `MCP.Value`,
  /// inlining `$defs` so the resulting schema is dereferenced.
  private static func jsonSchemaValue(from schema: GenerationSchema) -> Value? {
    guard
      let data = try? JSONEncoder().encode(schema),
      let value = try? JSONDecoder().decode(Value.self, from: data)
    else { return nil }

    guard case .object(var rootFields) = value else { return value }

    var defs: [String: Value] = [:]
    if case .object(let defsFields) = rootFields["$defs"] ?? .null {
      defs = defsFields
    }
    rootFields.removeValue(forKey: "$defs")

    return inline(.object(rootFields), defs: defs, visiting: [])
  }

  /// Recursively walks a `Value` and replaces `{"$ref": "#/$defs/X"}` with the
  /// corresponding inlined definition from `defs`. Guards against reference
  /// cycles via the `visiting` set.
  private static func inline(
    _ value: Value,
    defs: [String: Value],
    visiting: Set<String>
  ) -> Value {
    switch value {
    case .object(let fields):
      if fields.count == 1, case .string(let refString) = fields["$ref"] ?? .null {
        let name = refString.replacingOccurrences(of: "#/$defs/", with: "")
        guard !visiting.contains(name), let target = defs[name] else {
          return .object([
            "type": .string("object"),
            "additionalProperties": .bool(true),
          ])
        }
        var nextVisiting = visiting
        nextVisiting.insert(name)
        return inline(target, defs: defs, visiting: nextVisiting)
      }
      var out: [String: Value] = [:]
      for (key, child) in fields {
        out[key] = inline(child, defs: defs, visiting: visiting)
      }
      return .object(out)
    case .array(let items):
      return .array(items.map { inline($0, defs: defs, visiting: visiting) })
    default:
      return value
    }
  }
}
