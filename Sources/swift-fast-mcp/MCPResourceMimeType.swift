/// Compile-time safe MIME type for `@MCPResource`.
///
/// Common types are surfaced as explicit cases; unusual types travel through
/// `.other(String)`. Codable/Sendable so the value can flow through the macro
/// as a literal and round-trip through the MCP wire format.
public enum MCPResourceMimeType: Sendable, Hashable, Codable {
  case applicationJSON
  case applicationXML
  case applicationOctetStream
  case textPlain
  case textMarkdown
  case textHTML
  case textCSV
  case imagePNG
  case imageJPEG
  case other(String)

  public var rawValue: String {
    switch self {
    case .applicationJSON: return "application/json"
    case .applicationXML: return "application/xml"
    case .applicationOctetStream: return "application/octet-stream"
    case .textPlain: return "text/plain"
    case .textMarkdown: return "text/markdown"
    case .textHTML: return "text/html"
    case .textCSV: return "text/csv"
    case .imagePNG: return "image/png"
    case .imageJPEG: return "image/jpeg"
    case .other(let value): return value
    }
  }

  public init(_ rawValue: String) {
    switch rawValue {
    case "application/json": self = .applicationJSON
    case "application/xml": self = .applicationXML
    case "application/octet-stream": self = .applicationOctetStream
    case "text/plain": self = .textPlain
    case "text/markdown": self = .textMarkdown
    case "text/html": self = .textHTML
    case "text/csv": self = .textCSV
    case "image/png": self = .imagePNG
    case "image/jpeg": self = .imageJPEG
    default: self = .other(rawValue)
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = MCPResourceMimeType(try container.decode(String.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
