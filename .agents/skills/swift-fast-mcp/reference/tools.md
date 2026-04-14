# MCPTool Reference

## Content-Only Tools

```swift
public protocol MCPTool: Sendable {
  associatedtype Parameters
  associatedtype Schema: JSONSchemaComponent<Parameters>

  var name: String { get }
  var description: String? { get }
  var annotations: Tool.Annotations { get }

  @JSONSchemaBuilder
  var parameters: Schema { get }

  @ToolContentBuilder
  func call(with arguments: Parameters) async throws(ToolError) -> Content
}
```

- `Content` is a typealias for `[ToolContentItem]`
- `annotations` defaults to `nil`, but the type is `Tool.Annotations`, not `Tool.Annotations?`
- Plain `MCPTool` is the right choice when the result only needs human-readable content

## Structured Tools

```swift
public protocol MCPStructuredTool: MCPTool {
  associatedtype Output: Codable & Sendable
  associatedtype OutputSchema: JSONSchemaComponent<Output>

  @JSONSchemaBuilder
  var outputSchema: OutputSchema { get }

  func callStructured(with arguments: Parameters) async throws(ToolError)
    -> StructuredToolResult<Output>
}
```

Structured tools:

- publish `outputSchema` in `tools/list`
- return typed `structuredContent` in `tools/call`
- can still include normal text, image, audio, or resource content
- omit `structuredContent` automatically when they fail with `ToolError`

## Simple Tool

```swift
import FastMCP

public struct GreetingTool: MCPTool {
  public let name = "greet"
  public let description: String? = "Generate a greeting message"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let name: String
    public let formal: Bool?

    public init(name: String, formal: Bool? = nil) {
      self.name = name
      self.formal = formal
    }
  }

  public func call(with arguments: Parameters) async throws(ToolError) -> Content {
    let greeting =
      arguments.formal == true
      ? "Good day, \(arguments.name)."
      : "Hey \(arguments.name)!"
    return [ToolContentItem(text: greeting)]
  }
}
```

## Structured Tool Example

```swift
import FastMCP

public struct SearchTool: MCPStructuredTool {
  public typealias Output = SearchResult

  public let name = "search"
  public let description: String? = "Return structured search results"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let query: String
    public init(query: String) { self.query = query }
  }

  @Schemable
  public struct SearchResult: Codable, Sendable {
    public let summary: String
    public let resultCount: Int

    public init(summary: String, resultCount: Int) {
      self.summary = summary
      self.resultCount = resultCount
    }
  }

  public func callStructured(with arguments: Parameters) async throws(ToolError)
    -> StructuredToolResult<SearchResult>
  {
    let summary = "Found 2 results for \(arguments.query)"
    return StructuredToolResult(
      structuredContent: SearchResult(summary: summary, resultCount: 2)
    ) {
      ToolContentItem(text: summary)
    }
  }
}
```

## Tool Annotations

Annotations provide hints to clients about a tool's behavior:

```swift
public var annotations: Tool.Annotations {
  .init(
    readOnlyHint: true,
    destructiveHint: false,
    idempotentHint: true,
    openWorldHint: false
  )
}
```

Available annotation hints:

| Hint | Type | Default | Meaning |
|------|------|---------|---------|
| `readOnlyHint` | `Bool?` | `nil` | Tool does not modify state |
| `destructiveHint` | `Bool?` | `nil` | Tool may perform destructive operations |
| `idempotentHint` | `Bool?` | `nil` | Calling multiple times with same args has same effect |
| `openWorldHint` | `Bool?` | `nil` | Tool interacts with external entities |

## Error Handling

Use typed throws with `ToolError`:

```swift
throw ToolError("Division by zero")
```

`ToolError` content is returned with `isError: true`. Structured tools still omit
`structuredContent` on error.

## Registration

```swift
try await FastMCP.builder()
  .addTools([
    GreetingTool(),
    SearchTool(),
  ])
  .run()
```

Multiple `.addTools()` calls accumulate tools. Duplicates (same `name`) are silently dropped.
The first registration wins.

## Key Requirements

- Parameters structs should be annotated with `@Schemable`
- Parameters structs used by tools should conform to `Sendable`
- Structured outputs should conform to `Codable & Sendable`
- Add `public init()` for cross-module access
- `description` is `String?`
- Enum parameters need `@Schemable` and `String` raw values
