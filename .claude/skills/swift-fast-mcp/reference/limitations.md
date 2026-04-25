# Known Limitations

Source checks: `Sources/swift-fast-mcp/FastMCP.swift`,
`Sources/swift-fast-mcp/ServerHandle.swift`,
`Sources/swift-fast-mcp/Transport.swift`, and
`../swift-ai-hub/Sources/SwiftAIHub/Generation/GenerationGuide.swift`.

## No resource subscriptions

Resources are advertised with `subscribe: false`. Clients cannot subscribe
to resource change notifications. Catalogue-level
`notifications/resources/list_changed` is supported via
`FastMCPServerHandle`, but per-resource update notifications are not.

## Silent dedup for resources and prompts

`addResources(_:)` deduplicates by `uri` and `addPrompts(_:)` by `name`.
Duplicates are silently dropped — first registration wins. No warning is
logged.

## Tool dedup is loud

`addTools(_:)` is `throws` and rejects duplicate tool names eagerly with
`HubBridgeError.duplicateTool(name:)` (`Sources/swift-fast-mcp/FastMCP.swift:80`).
The same check fires inside `HubToolAdapter.register(_:)` and inside the
`FastMCPServerHandle.addTool(_:)` / `addTools(_:)` paths, so a duplicate
name is always a registration-time failure.

## `.inMemory` is unpaired

`Transport.inMemory` constructs a fresh `InMemoryTransport()` with no
peer. The MCP SDK's `connect()` requires a paired transport. For paired
in-process client/server tests, use `.custom(_:)` with one half of an
`InMemoryTransport.createConnectedPair()`. Detail: `docs/Transports.md`.

## Tool error mapping flattens domain errors

Any `Error` thrown from `execute(_:)` is wrapped as
`HubBridgeError.invalidArguments(tool:reason:)` and surfaces as
`isError: true` with the message `"Invalid arguments for <tool>: <reason>"`.
Custom error types reach the wire only through their textual
representation; they are not preserved as a distinct case. Detail:
`docs/Tools.md`.

## Schema constraints are partial

`@Generable` re-emits a subset of `GenerationGuide` constraints today
(array counts, numeric `Int`/`Double`/`Float` ranges, string
`.constant` / `.anyOf` / `.pattern`). `.element(_:)` intentionally stores no
element constraint, and dynamic `Regex(...)` patterns may not be observable
on older deployment targets. See `../swift-ai-hub/docs/Macros.md` for the
current cut.

## TLS is out of scope

The HTTP transport is plaintext. Deploy behind a reverse proxy (nginx,
Caddy) for HTTPS termination.

## Platform floor

`swift-tools-version: 6.2`. The `swift-fast-mcp` package itself targets
macOS 14+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+. A scaffolded
server target on macOS uses `platforms: [.macOS(.v14)]`.
