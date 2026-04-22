// Portions of this file are ported from swift-mcp-toolkit (Apache-2.0).
// See https://github.com/mehmetbaykar/swift-mcp-toolkit.

/// A generic result builder for constructing content declaratively.
///
/// This builder provides a flexible way to construct arrays of content items
/// using Swift's result builder syntax, supporting conditionals, loops, and optionals.
@resultBuilder
public enum ContentBuilder<Item> {
  public static func buildBlock(_ components: Item...) -> [Item] {
    components
  }

  public static func buildBlock(_ components: [Item]...) -> [Item] {
    components.flatMap { $0 }
  }

  public static func buildExpression(_ item: Item) -> Item {
    item
  }

  public static func buildExpression(_ items: [Item]) -> [Item] {
    items
  }

  public static func buildOptional(_ component: [Item]?) -> [Item] {
    component ?? []
  }

  public static func buildEither(first component: [Item]) -> [Item] {
    component
  }

  public static func buildEither(second component: [Item]) -> [Item] {
    component
  }

  public static func buildEither(first component: Item) -> [Item] {
    [component]
  }

  public static func buildEither(second component: Item) -> [Item] {
    [component]
  }

  public static func buildArray(_ components: [[Item]]) -> [Item] {
    components.flatMap { $0 }
  }
}

/// Groups multiple text strings into a single content item.
public struct Group<ContentItem>: Sendable where ContentItem: Sendable {
  internal let lines: [String]
  internal let separator: String

  public init(separator: String = "\n", @ArrayBuilder<String> _ content: () -> [String]) {
    self.lines = content()
    self.separator = separator
  }

  internal var joinedText: String {
    lines.joined(separator: separator)
  }
}

/// A result builder for constructing arrays of strings.
@resultBuilder
public enum ArrayBuilder<Element> {
  public static func buildBlock(_ components: Element...) -> [Element] {
    components
  }

  public static func buildOptional(_ component: [Element]?) -> [Element] {
    component ?? []
  }

  public static func buildEither(first component: [Element]) -> [Element] {
    component
  }

  public static func buildEither(second component: [Element]) -> [Element] {
    component
  }

  public static func buildArray(_ components: [[Element]]) -> [Element] {
    components.flatMap { $0 }
  }
}
