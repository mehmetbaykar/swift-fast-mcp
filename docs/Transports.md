# Transports

`swift-fast-mcp` exposes one server over four transport choices. Pick the
transport that matches how the client will reach you:

| Use case                                      | Transport     |
| --------------------------------------------- | ------------- |
| Claude Desktop, CLI host, local subprocess    | `.stdio`      |
| Web service, network deployment, remote agent | `.http(...)`  |
| Unpaired in-process transport                 | `.inMemory`   |
| Existing `MCP.Transport`, including test pairs | `.custom(_:)` |

Defined in
[`Sources/swift-fast-mcp/Transport.swift`](../Sources/swift-fast-mcp/Transport.swift):

```swift
public enum Transport: Sendable {
  case stdio
  case inMemory
  case http(
    mode: HTTPMode = .stateful,
    host: String = "127.0.0.1",
    port: Int = 3000,
    endpoint: String = "/mcp"
  )
  case custom(MCP.Transport)
}

public enum HTTPMode: Sendable {
  case stateful   // sessions, SSE streaming, GET/DELETE, resumability
  case stateless  // POST only, direct JSON responses
}
```

You select a transport with `.transport(_:)` on the builder. The default is
`.stdio`
([`FastMCP.swift:51`](../Sources/swift-fast-mcp/FastMCP.swift)).

## Stdio

```swift
try await FastMCP.builder()
  .name("my-server")
  .addTools(tools)
  .transport(.stdio)
  .run()
```

The server reads framed JSON-RPC from `stdin` and writes responses to `stdout`.
Logging goes to `stderr` so it cannot corrupt the protocol stream. This is the
transport Claude Desktop, the Claude CLI, and most local MCP hosts launch as a
subprocess; the host owns the process lifetime.

Use stdio when:

- The client is a desktop app or CLI that launches your binary directly.
- You're piping JSON-RPC through `stdin`/`stdout` for scripting.
- You don't need network exposure.

The transport is constructed via the upstream SDK's `StdioTransport`
([`FastMCP.swift:378`](../Sources/swift-fast-mcp/FastMCP.swift)) and runs inside
a `ServiceGroup` so `onStart`/`onShutdown`/signal handling work uniformly across
all transports.

## HTTP

```swift
try await FastMCP.builder()
  .name("my-server")
  .addTools(tools)
  .transport(.http(
    mode: .stateful,
    host: "0.0.0.0",
    port: 8080,
    endpoint: "/mcp"
  ))
  .httpValidation(allowedOrigins: ["https://app.example.com"])
  .run()
```

Bound by NIO in
[`Internal/HTTPServer.swift`](../Sources/swift-fast-mcp/Internal/HTTPServer.swift).
The server listens on `host:port`, routes only `endpoint` (404 otherwise), and
speaks JSON-RPC over `POST`. In stateful mode it also supports `GET` (SSE
stream) and `DELETE` (terminate session).

Defaults from `Transport.http`:

- `mode: .stateful`
- `host: "127.0.0.1"`
- `port: 3000`
- `endpoint: "/mcp"`

## Upstream Streamable HTTP aggregation

The `.transport(...)` setting above controls how clients connect to your
FastMCP server. Upstream MCP aggregation is configured separately with
`addUpstreamMCPServer(...)`, and currently supports Streamable HTTP upstreams:

```swift
try await FastMCP.builder()
  .name("Gateway")
  .addUpstreamMCPServer(
    name: "docs",
    transport: .streamableHTTP(
      endpoint: URL(string: "https://example.com/mcp")!,
      headers: ["Authorization": "Bearer <token>"]
    )
  )
  .transport(.http(port: 8080))
  .run()
```

This uses the official SDK's `HTTPClientTransport`, which implements MCP
Streamable HTTP. The API is named `.streamableHTTP` to distinguish it from older
remote MCP transports that used separate event and message endpoints. Streamable
HTTP uses regular HTTP POST/GET with optional event-stream responses internally,
and the SDK handles session IDs, protocol version headers, JSON responses, and
streaming.

FastMCP does not launch upstream stdio subprocesses in this version. If an
upstream MCP server is only available as `npx`, `uvx`, or `python -m`, run or
wrap that server behind a Streamable HTTP endpoint before aggregating it.
The upstream `name` is used as the default visible tool prefix (`docs_search`);
pass `toolNamePrefix` only to customize the namespace or `""` to opt out. V1
does not aggregate upstream resources/prompts, reconnect automatically, or
subscribe to upstream `notifications/tools/list_changed`. Treat sensitive
headers, especially `Authorization`, as secrets and avoid verbose request
logging in production.

### Stateful vs stateless

`.stateful` runs the full Streamable HTTP profile. The first `POST` carrying
`"method": "initialize"` creates a session; subsequent requests must include the
returned `MCP-Session-Id` header. Sessions support SSE streaming, server -> client
notifications, resumability, and explicit teardown via `DELETE`. Idle sessions
expire after `sessionTimeout` (default `.seconds(3600)`, change with
`.sessionTimeout(_:)`); a background loop sweeps every 60 s
([`FastMCP.swift:62`](../Sources/swift-fast-mcp/FastMCP.swift),
[`FastMCP.swift:143`](../Sources/swift-fast-mcp/FastMCP.swift),
[`HTTPServer.swift:281`](../Sources/swift-fast-mcp/Internal/HTTPServer.swift)).
Choose `.stateful` for interactive clients that need streaming or progress.

`.stateless` answers each `POST` with a direct JSON response and no session
tracking — `GET`/`DELETE` are not used. A single `StatelessHTTPServerTransport`
serves every request
([`HTTPServer.swift:119`](../Sources/swift-fast-mcp/Internal/HTTPServer.swift)).
Choose `.stateless` for fan-out behind a load balancer, serverless deployments,
or simple request/response tools where session continuity isn't needed.

### `httpValidation(allowedOrigins:customValidators:)`

```swift
public func httpValidation(
  allowedOrigins: [String]? = nil,
  customValidators: [any HTTPRequestValidator] = []
) -> Builder
```

`httpValidation` wires a request-validation pipeline in front of every HTTP
request
([`FastMCP.swift:241`](../Sources/swift-fast-mcp/FastMCP.swift)). It only
applies when the transport is `.http(...)`.

- `allowedOrigins` — when non-nil and non-empty, builds an `OriginValidator`
  (from `swift-sdk`) with `allowedHosts: [host]` and your origin allowlist. This
  enforces same-origin / explicit-origin checks against the `Origin` and `Host`
  headers, blocking DNS-rebinding and cross-site attacks against a server bound
  to localhost. Pass `nil` (the default) to disable origin checks.
- `customValidators` — an ordered list of types conforming to the SDK's
  `HTTPRequestValidator` protocol. Use these for bearer tokens, content-type
  enforcement, custom headers, or anything else you'd reject before reaching
  JSON-RPC. The SDK ships `BearerTokenValidator`, `AcceptHeaderValidator`,
  `ContentTypeValidator`, `ProtocolVersionValidator`, and `SessionValidator`.

If both arguments are empty/nil the pipeline is `nil` and no validation runs.
Otherwise a `StandardValidationPipeline` runs the origin validator first, then
your custom validators in order.

Custom validators implement
`func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse?`:
return `nil` to continue, or return a response to short-circuit the pipeline.

```swift
import Foundation
import FastMCP
import MCP

let secret = "shared-secret"
let bearerValidator = BearerTokenValidator(
  resourceMetadataURL: URL(string: "https://api.example.com/.well-known/oauth-protected-resource")!,
  resourceIdentifier: URL(string: "https://api.example.com")!,
  tokenValidator: { token, _, _ in
    token == secret
      ? .valid(BearerTokenInfo())
      : .invalidToken(errorDescription: "Invalid bearer token")
  }
)

let server = FastMCP.builder()
  .transport(.http(host: "0.0.0.0", port: 8080))
  .httpValidation(
    allowedOrigins: ["https://app.example.com"],
    customValidators: [bearerValidator]
  )
```

## ServiceGroup lifecycle

Every transport path is wrapped in a `swift-service-lifecycle` `ServiceGroup`
with the configured shutdown signals
([`FastMCP.swift:326`](../Sources/swift-fast-mcp/FastMCP.swift),
[`Internal/Service.swift`](../Sources/swift-fast-mcp/Internal/Service.swift),
[`Internal/HTTPService.swift`](../Sources/swift-fast-mcp/Internal/HTTPService.swift)):

```swift
.shutdownSignals([.sigterm, .sigint])  // default
.onStart { await metrics.serverStarted() }
.onShutdown { await metrics.serverStopped() }
```

- For stdio / in-memory / custom, `onStart` fires before `server.start(...)`,
  then `server.waitUntilCompleted()` waits until the server stops, then
  `onShutdown` runs.
- For HTTP, `onStart` fires before `httpServer.start()`. On graceful shutdown,
  the service calls `httpServer.stop()`, then `onShutdown` runs after
  `httpServer.start()` returns.
- `shutdownSignals` defaults to `[.sigterm, .sigint]`
  ([`FastMCP.swift:53`](../Sources/swift-fast-mcp/FastMCP.swift)) — pass an
  empty array to opt out, or add e.g. `.sighup`. The `ServiceGroup` receives the
  configured signal list for both HTTP and non-HTTP transports.
- `httpServer.stop()` closes all sessions, disconnects the stateless transport
  if present, and closes the listening channel
  ([`HTTPServer.swift:142`](../Sources/swift-fast-mcp/Internal/HTTPServer.swift)).

`run()` is `async throws` and only returns once the group has stopped.

## In-memory

```swift
.transport(.inMemory)
```

`FastMCP` calls `InMemoryTransport()` (from the swift-sdk MCP module) when you
select `.inMemory`
([`FastMCP.swift:380`](../Sources/swift-fast-mcp/FastMCP.swift)). That creates a
fresh, unpaired transport. The SDK's `connect()` requires a paired transport and
throws when none is present, so paired in-process client/server tests should use
`.custom(_:)` with one half of a connected pair:

```swift
let (clientTransport, serverTransport) =
  await InMemoryTransport.createConnectedPair()

let serverTask = Task {
  try await FastMCP.builder()
    .addTools(tools)
    .transport(.custom(serverTransport))
    .run()
}

let client = Client(name: "test", version: "1.0.0")
try await client.connect(transport: clientTransport)
// ... drive the server, then:
serverTask.cancel()
```

## Custom

```swift
.transport(.custom(myTransport))  // myTransport: MCP.Transport
```

Pass any value conforming to the `MCP.Transport` protocol from the upstream
[`swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk). Use this to
plug in a transport the framework doesn't ship — WebSocket, named pipes, an
in-process bridge, or one half of an `InMemoryTransport` pair as shown above.
Validation (`httpValidation`) does not apply to custom transports; if your
transport needs per-request validation, build it into the transport itself.
