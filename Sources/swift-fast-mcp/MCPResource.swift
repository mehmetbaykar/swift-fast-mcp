/// A strongly typed interface for exposing resources in a Model Context Protocol server.
///
/// Conforming types define the URI for their resource and provide content using a declarative
/// result builder syntax.
public protocol MCPResource: Sendable {
  typealias Content = [ResourceContentItem]

  var uri: String { get }
  var name: String? { get }
  var description: String? { get }
  var mimeType: String? { get }

  @ResourceContentBuilder
  var content: Content { get async throws }
}

extension MCPResource {
  public var name: String? { nil }
  public var description: String? { nil }
  public var mimeType: String? { nil }
}

/// A result builder for constructing resource content declaratively.
public typealias ResourceContentBuilder = ContentBuilder<ResourceContentItem>

extension ContentBuilder where Item == ResourceContentItem {
  public static func buildExpression(_ group: ResourceGroup) -> ResourceContentItem {
    group.asContentItem()
  }
}

/// Represents a single content item with optional MIME type metadata.
public struct ResourceContentItem: Sendable, ExpressibleByStringLiteral,
  ExpressibleByStringInterpolation
{
  public enum ContentType: Sendable {
    case text(String)
    case blob(String)
  }

  public let content: ContentType
  public let mimeType: String?

  public init(text: String, mimeType: String? = nil) {
    self.content = .text(text)
    self.mimeType = mimeType
  }

  public init(base64Blob: String, mimeType: String) {
    self.content = .blob(base64Blob)
    self.mimeType = mimeType
  }

  public init(stringLiteral value: String) {
    self.content = .text(value)
    self.mimeType = nil
  }

  public func mimeType(_ type: String) -> ResourceContentItem {
    ResourceContentItem(content: content, mimeType: type)
  }

  private init(content: ContentType, mimeType: String?) {
    self.content = content
    self.mimeType = mimeType
  }
}

extension ResourceContentItem {
  public static func blob(_ base64Data: String, mimeType: String) -> ResourceContentItem {
    ResourceContentItem(base64Blob: base64Data, mimeType: mimeType)
  }
}

/// Specialized version of Group that supports MIME types for resources.
public struct ResourceGroup: Sendable {
  private let lines: [String]
  private let separator: String
  private let mimeType: String?

  public init(separator: String = "\n", @ArrayBuilder<String> _ content: () -> [String]) {
    self.lines = content()
    self.separator = separator
    self.mimeType = nil
  }

  private init(lines: [String], separator: String, mimeType: String?) {
    self.lines = lines
    self.separator = separator
    self.mimeType = mimeType
  }

  public func mimeType(_ type: String) -> ResourceGroup {
    ResourceGroup(lines: lines, separator: separator, mimeType: type)
  }

  fileprivate func asContentItem() -> ResourceContentItem {
    ResourceContentItem(
      text: lines.joined(separator: separator),
      mimeType: mimeType
    )
  }
}
