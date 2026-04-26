# Dynamic servers

Most FastMCP servers know their full catalogue at start-up: pass tools, resources,
and prompts to the builder, call `run()`, done. This document is for the other
case — when you need to mutate the catalogue *after* `run()` has started serving
clients. Hot reloads on config change, plug-in load events, admin commands,
multi-tenant servers that grow new tools per session — anything where the set of
exposed capabilities is not fixed at boot.

## When to reach for a handle

Use the static builder when the catalogue is fixed:

```swift
try await FastMCP.builder()
  .addTools([WeatherTool(), MathTool()])
  .addResources([ConfigResource()])
  .transport(.stdio)
  .run()
```

Reach for `FastMCPServerHandle` only when you need post-start mutation. The
handle is a `public actor` (`Sources/swift-fast-mcp/ServerHandle.swift`); you
keep a long-lived reference to it alongside the task running the server, then
call its mutation methods from anywhere — a config-file watcher, an admin RPC,
a plug-in loader, etc.

## Construction

Build the handle, hand it to the builder, await `run()`:

```swift
let handle = FastMCPServerHandle()

try await FastMCP.builder()
  .addTools([WeatherTool()])     // initial seed
  .serverHandle(handle)
  .transport(.stdio)
  .run()
```

`serverHandle(_:)` is defined as
`public func serverHandle(_ handle: FastMCPServerHandle) -> Builder`
(`Sources/swift-fast-mcp/FastMCP.swift`). The seed passed via
`addTools` / `addResources` / `addPrompts` is copied into the handle during
`run()` via the internal
`configure(toolAdapter:resources:prompts:)` method
(`Sources/swift-fast-mcp/ServerHandle.swift`;
call site `FastMCP.swift`). Any mutations made on the handle *before*
it reaches `run()` are overwritten. Build the seed with the builder; use the
handle for post-start mutations only.

For non-HTTP transports, `run()` registers the initial handlers on one
`MCP.Server`, then calls `registerServer(_:)` to put that server under handle
tracking (`Sources/swift-fast-mcp/FastMCP.swift`;
`Sources/swift-fast-mcp/ServerHandle.swift`).

The internal handle methods used by `run()` are
`func configure(toolAdapter: HubToolAdapter, resources: [any MCPResource], prompts: [any MCPPrompt])`,
`func registerServer(_ server: Server)`,
`func registerHTTPSession(_ server: Server) async`, and
`func activateHTTPSession(_ server: Server) async`
(`Sources/swift-fast-mcp/ServerHandle.swift`).

## Mutating the catalogue

All public mutation methods shown below are `async`. Tool add methods are
`throws` for duplicate names; tool removal is non-throwing. Resource and prompt
methods call the deduplicators and are non-throwing
(`Sources/swift-fast-mcp/ServerHandle.swift`).

### Tools

```swift
try await handle.addTool(MathTool())                            // public func addTool(_ tool: any SwiftAIHub.Tool) async throws
try await handle.addTools([MathTool(), GeoTool()])              // public func addTools(_ newTools: [any SwiftAIHub.Tool]) async throws
await handle.removeTool(named: "weather")                       // public func removeTool(named name: String) async
let adapter = await handle.currentToolAdapter
```

`addTools(_:)` validates the whole batch up front against existing names and
duplicates inside the batch before mutating the adapter. A duplicate anywhere in the batch fails
with `HubBridgeError.duplicateTool` before any item from that batch is
committed.
`removeTool(named:)` is idempotent: removing an unknown name is a no-op and
emits no notification.

### Upstream MCP servers

When the running server has a handle, you can also add, remove, or refresh
upstream Streamable HTTP MCP servers dynamically:

```swift
try await handle.addUpstreamMCPServer(
  UpstreamMCPServerConfiguration(
    name: "firecrawl",
    transport: .streamableHTTP(
      endpoint: URL(string: "https://mcp.firecrawl.dev/v2/mcp")!,
      headers: ["Authorization": "Bearer <token>"]
    )
  )
)

try await handle.refreshUpstreamMCPServer(named: "firecrawl")
try await handle.removeUpstreamMCPServer(named: "firecrawl")
```

`addUpstreamMCPServer(_:)` connects to the upstream server, discovers every page
of `tools/list`, registers the visible proxied tools, and then emits
`notifications/tools/list_changed`. The upstream server name is the default tool
namespace, so `name: "firecrawl"` exposes `firecrawl_scrape`; pass a custom
`toolNamePrefix` to override it or `toolNamePrefix: ""` to expose raw names.
`refreshUpstreamMCPServer(named:)` discovers a fresh upstream tool list and swaps
that server's proxied entries atomically: if the refreshed visible names collide
with existing local or upstream tools, the old entries remain visible and the
refresh throws. It only notifies when the discovered tool descriptors changed.
`removeUpstreamMCPServer` disconnects the upstream client, removes every tool
from that upstream server, and notifies only when something changed.

Only Streamable HTTP upstreams are supported here. Stdio subprocess upstreams
are intentionally not part of this API. V1 aggregates upstream tools only; it
does not proxy upstream resources, prompts, automatic reconnect/backoff, or
upstream `notifications/tools/list_changed`. If you pass sensitive headers such
as `Authorization`, keep production logging conservative so request metadata is
not accidentally surfaced by lower-level transports.

### Resources

```swift
await handle.addResource(ConfigResource())                      // public func addResource(_ resource: any MCPResource) async
await handle.addResources([LogResource(), MetricsResource()])   // public func addResources(_ newResources: [any MCPResource]) async
await handle.removeResource(uri: "file:///etc/config.json")     // public func removeResource(uri: String) async
let resources = await handle.currentResources
```

### Prompts

```swift
await handle.addPrompt(GreetingPrompt())                        // public func addPrompt(_ prompt: any MCPPrompt) async
await handle.addPrompts([SummarizePrompt(), TranslatePrompt()]) // public func addPrompts(_ newPrompts: [any MCPPrompt]) async
await handle.removePrompt(named: "greeting")                    // public func removePrompt(named name: String) async
let prompts = await handle.currentPrompts
```

## listChanged notifications

When a handle is attached, the builder flips the `listChanged` flag on every
advertised capability (tools, resources, prompts) by passing
`listChanged: true` to `CapabilitiesBuilder.build(...)`
(`Sources/swift-fast-mcp/FastMCP.swift`). Those capabilities are passed to each
`Server` created by `run()`, so the server may push:

- `notifications/tools/list_changed`
- `notifications/resources/list_changed`
- `notifications/prompts/list_changed`

The handle emits notifications from three private helpers:
`notifyToolsChanged()`, `notifyResourcesChanged()`, and
`notifyPromptsChanged()` (`Sources/swift-fast-mcp/ServerHandle.swift`). Each helper walks the
tracked `Server` list, calls the matching MCP notification message, and records
servers whose `notify(...)` call throws. It then prunes those servers with
`removeServers(at:)`.

The mutation paths differ:

**Tools** - `addTool(_:)` and `addTools(_:)` mutate the shared `HubToolAdapter`
and then notify. `removeTool(named:)` unregisters
from the adapter and notifies only when the name existed
(`Sources/swift-fast-mcp/ServerHandle.swift`).

**Resources and prompts** - add methods write the deduplicated array,
re-register handlers on every tracked server, then notify
(`Sources/swift-fast-mcp/ServerHandle.swift`). Remove methods
re-register and notify only when the item existed
(`Sources/swift-fast-mcp/ServerHandle.swift`). The
re-registration helpers loop over tracked servers and call
`server.register(resources:)` or `server.register(prompts:)`
(`Sources/swift-fast-mcp/ServerHandle.swift`).

## Stateful HTTP — per-session servers under one handle

Stateful HTTP transport spawns one `MCP.Server` per session. The handle tracks
all of them so a single mutation reaches every active session.

The flow per new session (`Sources/swift-fast-mcp/FastMCP.swift`):

1. The HTTP server invokes the session factory.
2. The factory builds an `MCP.Server` and calls
   `await handle.registerHTTPSession(server)`, which registers handlers for
   the *current* tool adapter, resources, and prompts on that server but does
   *not* yet add it to the tracking list.
3. The factory calls `server.start(transport:initializeHook:)`.
4. After `start` returns, the factory calls
   `await handle.activateHTTPSession(server)`, which appends the server to the
   tracking list and re-registers resources and prompts in case the catalogue
   changed during start-up.

The split exists to avoid a race documented in the source: notifying a server
that has not yet finished `start(...)` can throw
`connection-not-initialized`, and the prune logic would remove that server from
tracking before it served requests (`Sources/swift-fast-mcp/ServerHandle.swift`). Registering
before `start` and tracking after `start` closes that window.

A subsequent `await handle.addTool(...)` mutates the handle's `toolAdapter` and
emits one notification per server in the tracking list. Stateless HTTP
follows the same factory pattern (`Sources/swift-fast-mcp/FastMCP.swift`).

## Concurrency

`FastMCPServerHandle` is declared as a `public actor`
(`Sources/swift-fast-mcp/ServerHandle.swift`), so calls into the handle serialize on the actor's
executor. Three things follow:

- **Mutations are awaited.** Every public mutation method is `async`.
  `try await handle.addTool(...)` returns once the adapter registration and tool
  notification pass finish.
- **Hot-reload bursts are safe.** Concurrent calls to `addTool` / `removeTool`
  / `addResource` / etc. from different tasks are linearised; no extra locking
  is needed at call sites.
- **Notification fan-out runs on the actor.** A mutation that notifies many
  sessions holds the actor until fan-out finishes.
  Batch with `addTools(_:)` when one notification for the whole tool batch is
  the intended behavior.

For typical hot-reload patterns — a config-file watcher rebuilding the tool
list on file change — call the handle directly from the watcher's task. The
actor handles the rest:

```swift
let handle = FastMCPServerHandle()

Task {
  try await FastMCP.builder()
    .serverHandle(handle)
    .transport(.http(mode: .stateful, host: "127.0.0.1", port: 8080))
    .run()
}

for await change in configWatcher.changes {
  let newTools = try buildTools(from: change.config)
  let oldNames = await handle.currentToolAdapter.names()
  for name in oldNames { await handle.removeTool(named: name) }
  try await handle.addTools(newTools)
}
```

Every tracked server gets one `tools/list_changed` attempt per successful
`removeTool(named:)` that removed a name and one for the final `addTools(_:)`
call.
