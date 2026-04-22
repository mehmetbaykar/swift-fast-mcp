// swift-fast-mcp — FastMCPAIBridge
// Bridges SwiftAIHub.GeneratedContent ↔ MCP.Value.

import Foundation
import MCP
import SwiftAIHub

public enum HubValueMapper {
  /// Convert an MCP wire value into hub GeneratedContent.
  public static func generatedContent(from value: Value) -> GeneratedContent {
    switch value {
    case .null:
      return GeneratedContent(kind: .null)
    case .bool(let b):
      return GeneratedContent(kind: .bool(b))
    case .int(let i):
      return GeneratedContent(kind: .number(Double(i)))
    case .double(let d):
      return GeneratedContent(kind: .number(d))
    case .string(let s):
      return GeneratedContent(kind: .string(s))
    case .array(let arr):
      return GeneratedContent(kind: .array(arr.map { generatedContent(from: $0) }))
    case .object(let obj):
      var properties: [String: GeneratedContent] = [:]
      var orderedKeys: [String] = []
      for (key, value) in obj {
        properties[key] = generatedContent(from: value)
        orderedKeys.append(key)
      }
      return GeneratedContent(kind: .structure(properties: properties, orderedKeys: orderedKeys))
    case .data(let mime, let data):
      let encoded = data.base64EncodedString()
      let prefix = mime.map { "data:\($0);base64," } ?? ""
      return GeneratedContent(kind: .string(prefix + encoded))
    }
  }

  /// Convert hub GeneratedContent back into an MCP wire value.
  public static func value(from content: GeneratedContent) -> Value {
    switch content.kind {
    case .null:
      return .null
    case .bool(let b):
      return .bool(b)
    case .number(let n):
      if n.truncatingRemainder(dividingBy: 1) == 0, let i = Int(exactly: n) {
        return .int(i)
      }
      return .double(n)
    case .string(let s):
      return .string(s)
    case .array(let arr):
      return .array(arr.map { value(from: $0) })
    case .structure(let properties, let orderedKeys):
      var object: [String: Value] = [:]
      for key in orderedKeys {
        if let v = properties[key] {
          object[key] = value(from: v)
        }
      }
      return .object(object)
    }
  }
}
