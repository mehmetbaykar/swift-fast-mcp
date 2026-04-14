# Known Limitations

## No Resource Subscriptions

Resources are built with `subscribe: false`. Clients cannot subscribe to resource change notifications.

## Silent Deduplication

When duplicate tools (same name), resources (same URI), or prompts (same name) are registered, the duplicates are silently dropped without any warning or log message. The first registration wins.

## Linux Support

The HTTP transport works on Linux. The stdio and inMemory transports also work on Linux. The package compiles on Linux with Swift 6.2+.

## macOS 14+ Only

The package requires macOS 14+ (`platforms: [.macOS(.v14)]`). No iOS, watchOS, tvOS, or visionOS support.

## Swift 6.2+

The package requires Swift 6.2+ (`swift-tools-version: 6.2`).
