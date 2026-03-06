# Known Limitations

## No Dynamic List Changes

All capabilities are built with `listChanged: false`:

```swift
Server.Capabilities(
  prompts: hasPrompts ? .init(listChanged: false) : nil,
  resources: hasResources ? .init(subscribe: false, listChanged: false) : nil,
  tools: hasTools ? .init(listChanged: false) : nil
)
```

The server cannot notify clients when tools, resources, or prompts are added/removed at runtime. All components must be registered at startup.

## No Resource Subscriptions

Resources are built with `subscribe: false`. Clients cannot subscribe to resource change notifications.

## No Built-in HTTP/SSE Transport

Only `.stdio` and `.inMemory` transports are built-in. For HTTP/SSE, use `.custom(transport)` with a custom `MCP.Transport` implementation.

## Silent Deduplication

When duplicate tools (same name), resources (same URI), or prompts (same name) are registered, the duplicates are silently dropped without any warning or log message. The first registration wins.

## Sampling is Flag-Only

`enableSampling()` sets a capability flag in the MCP handshake but delegates actual sampling to the MCP SDK. There is no custom sampling surface in FastMCP.

## Unreachable Error Cases

`FastMCPError` defines HTTP-related cases that are not currently reachable:
- `.portInUse(Int)` — no HTTP server to bind ports
- `.authRequiredForHTTP` — no HTTP transport built-in

These exist for potential future HTTP transport support.

## macOS 14+ Only

The package requires macOS 14+ (`platforms: [.macOS(.v14)]`). No iOS, watchOS, tvOS, or visionOS support.

## Swift 6.2+

The package requires Swift 6.2+ (`swift-tools-version: 6.2`).
