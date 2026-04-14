# MCPResource Reference

## Protocol

```swift
public protocol MCPResource: Sendable {
  var uri: String { get }
  var name: String { get }
  var description: String? { get }
  var mimeType: String? { get }
  var content: Content { get async throws }
}
```

- `Content` can be a string literal (auto-converted) or `[ResourceContentItem]`
- The `content` property can be synchronous or `async throws`

## Static Resource

```swift
import FastMCP

public struct ConfigResource: MCPResource {
  public let uri: String
  public let name: String
  public let description: String?
  public let mimeType: String?

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

  public init() {
    self.uri = "config://app/settings"
    self.name = "App Settings"
    self.description = "Application configuration and feature flags"
    self.mimeType = "application/json"
  }
}
```

String literals are automatically converted to the appropriate `Content` type.

## Plain Text Resource

```swift
import FastMCP

public struct SystemInfoResource: MCPResource {
  public let uri = "system://info"
  public let name = "System Information"
  public let description: String? = "Current system information"
  public let mimeType: String? = "text/plain"

  public init() {}

  public var content: Content {
    """
    OS: Ubuntu
    Architecture: x86_64
    Swift Version: 6.2
    """
  }
}
```

## Async Resource

For resources that need to fetch data dynamically:

```swift
import FastMCP
import Foundation

public struct LiveDataResource: MCPResource {
  public let uri = "data://live/metrics"
  public let name = "Live Metrics"
  public let description: String? = "Current system metrics"
  public let mimeType: String? = "application/json"

  public init() {}

  public var content: Content {
    get async throws {
      // Fetch data dynamically
      let uptime = ProcessInfo.processInfo.systemUptime
      return """
      {"uptime": \(uptime)}
      """
    }
  }
}
```

## URI Conventions

- Use scheme-based URIs: `config://app/settings`, `system://info`, `data://live/metrics`
- URIs must be unique across all resources (used for deduplication)

## MIME Types

Common MIME types for resources:
- `application/json` — JSON data
- `text/plain` — plain text
- `text/html` — HTML content
- `text/markdown` — Markdown content

## Registration

```swift
try await FastMCP.builder()
  .addResources([
    ConfigResource(),
    SystemInfoResource(),
    LiveDataResource(),
  ])
  .run()
```

Multiple `.addResources()` calls accumulate resources. Duplicates (same `uri`) are silently dropped — first registration wins.

## Key Requirements

- Resource struct needs `public init()`
- `uri` must be unique across all registered resources
- `description` and `mimeType` types are `String?`
- `content` can be a computed property (sync) or `async throws`
- String literals work directly as `Content` return values
