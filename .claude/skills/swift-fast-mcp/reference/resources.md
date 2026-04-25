# `@MCPResource` Reference

Resources are authored with the `@MCPResource` macro from
`Sources/swift-fast-mcp/FastMCPMacros.swift` and implemented by
`Sources/FastMCPMacros/MCPResourceMacro.swift`. The macro turns a struct into
an `MCPResource`; the struct supplies its body with the
`@ResourceContentBuilder` result builder. Full reference:
[`docs/PromptsResources.md`](../../../../docs/PromptsResources.md).

## Macro shape

```swift
@MCPResource(
  _ uri: String,
  name: String? = nil,
  description: String? = nil,
  mimeType: MCPResourceMimeType? = nil
)
```

Applied to a struct, the macro emits:

- `public var uri: String`
- `public var name: String?` only when `name:` is present
- `public var description: String?` only when `description:` is present
- `public var mimeType: String?` only when `mimeType:` resolves
- `public init()` only when the struct has no user-declared init
- `extension … : MCPResource, Sendable`

The macro does *not* emit `content`. The struct must satisfy the
`MCPResource` protocol by declaring a content property:

```swift
@ResourceContentBuilder
public var content: Content { … }
```

`Content` is `[ResourceContentItem]` from
`Sources/swift-fast-mcp/MCPResource.swift`. `ResourceContentItem` stores either
`.text(String)` or `.blob(String)` plus an optional per-item MIME type, and
is `ExpressibleByStringLiteral` so a bare string literal is a valid
`Content` body.

## Canonical Example

From `Sources/ExampleTools/ConfigResource.swift`:

```swift
import FastMCP

@MCPResource(
  "config://app/settings",
  name: "App Settings",
  description: "Application configuration and feature flags",
  mimeType: .applicationJSON
)
public struct ConfigResource {
  @ResourceContentBuilder
  public var content: Content {
    """
    {
      "version": "1.0.0",
      "environment": "development",
      "features": {
        "darkMode": true,
        "notifications": true
      }
    }
    """
  }
}
```

`resources/list` publishes `name`, `uri`, `description`, and `mimeType`
straight from the macro arguments. `resources/read` returns a `contents`
array; FastMCP sets the per-item `mimeType` from `ResourceContentItem`,
not from the resource-level `mimeType`. A bare string-literal body therefore
publishes without a per-item MIME type. The wire shapes are shown in
`docs/PromptsResources.md`.

## Async / dynamic content

`MCPResource.content` is declared `{ get async throws }`. Use `async throws`
when the body needs to fetch:

```swift
@MCPResource("data://live/metrics", name: "Live Metrics", mimeType: .applicationJSON)
public struct LiveMetricsResource {
  @ResourceContentBuilder
  public var content: Content {
    get async throws {
      let uptime = ProcessInfo.processInfo.systemUptime
      ResourceContentItem(text: "{\"uptime\":\(uptime)}", mimeType: "application/json")
    }
  }
}
```

## Blob payloads

`ResourceContentItem.blob(_:mimeType:)` carries a base64-encoded payload and
emits `blob` instead of `text` on the wire, with `mimeType` always set.

## `MCPResourceMimeType`

The compile-time-safe MIME enum
(`Sources/swift-fast-mcp/MCPResourceMimeType.swift`):

| Case | `rawValue` |
|---|---|
| `.applicationJSON` | `application/json` |
| `.applicationXML` | `application/xml` |
| `.applicationOctetStream` | `application/octet-stream` |
| `.textPlain` | `text/plain` |
| `.textMarkdown` | `text/markdown` |
| `.textHTML` | `text/html` |
| `.textCSV` | `text/csv` |
| `.imagePNG` | `image/png` |
| `.imageJPEG` | `image/jpeg` |
| `.other(String)` | the associated string literal |

`@MCPResource` accepts bare-dot cases (`.applicationJSON`) and
`.other("custom/mime")` with a string literal.

## Registration

```swift
try await FastMCP.builder()
  .addResources([ConfigResource(), SystemInfoResource()])
  .run()
```

`addResources(_:)` accumulates across calls and deduplicates by `uri`.
First registration wins; duplicates are silently dropped.
