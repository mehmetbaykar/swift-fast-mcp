import Foundation
import Logging
import MCP
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

actor FastMCPHTTPServer {

  struct Configuration: Sendable {
    var host: String
    var port: Int
    var endpoint: String
    var sessionTimeout: TimeInterval
    var retryInterval: Int?

    init(
      host: String = "127.0.0.1",
      port: Int = 3000,
      endpoint: String = "/mcp",
      sessionTimeout: TimeInterval = 3600,
      retryInterval: Int? = nil
    ) {
      self.host = host
      self.port = port
      self.endpoint = endpoint
      self.sessionTimeout = sessionTimeout
      self.retryInterval = retryInterval
    }
  }

  typealias ServerFactory = @Sendable (String, StatefulHTTPServerTransport) async throws -> Server
  typealias StatelessServerFactory = @Sendable (StatelessHTTPServerTransport) async throws -> Server

  struct SessionContext: Sendable {
    let server: Server
    let transport: StatefulHTTPServerTransport
    let createdAt: Date
    var lastAccessedAt: Date
  }

  private enum Mode: Sendable {
    case stateful(ServerFactory)
    case stateless(StatelessServerFactory)
  }

  private let configuration: Configuration
  private let mode: Mode
  let validationPipeline: (any HTTPRequestValidationPipeline)?
  nonisolated let logger: Logger

  private var channel: Channel?
  private var sessions: [String: SessionContext] = [:]

  private var statelessTransport: StatelessHTTPServerTransport?
  private var statelessServer: Server?

  init(
    configuration: Configuration = Configuration(),
    validationPipeline: (any HTTPRequestValidationPipeline)? = nil,
    serverFactory: @escaping ServerFactory,
    logger: Logger? = nil
  ) {
    self.configuration = configuration
    self.mode = .stateful(serverFactory)
    self.validationPipeline = validationPipeline
    self.logger =
      logger
      ?? Logger(
        label: "fast-mcp.http.server",
        factory: { _ in SwiftLogNoOpLogHandler() }
      )
  }

  init(
    configuration: Configuration = Configuration(),
    validationPipeline: (any HTTPRequestValidationPipeline)? = nil,
    statelessServerFactory: @escaping StatelessServerFactory,
    logger: Logger? = nil
  ) {
    self.configuration = configuration
    self.mode = .stateless(statelessServerFactory)
    self.validationPipeline = validationPipeline
    self.logger =
      logger
      ?? Logger(
        label: "fast-mcp.http.server",
        factory: { _ in SwiftLogNoOpLogHandler() }
      )
  }

  func start() async throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    let bootstrap = ServerBootstrap(group: group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
          channel.pipeline.addHandler(NIOHTTPHandler(server: self))
        }
      }
      .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
      .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

    logger.info(
      "Starting FastMCP HTTP server",
      metadata: [
        "host": "\(configuration.host)",
        "port": "\(configuration.port)",
        "endpoint": "\(configuration.endpoint)",
      ]
    )

    if case .stateless(let factory) = mode {
      let transport = StatelessHTTPServerTransport(
        validationPipeline: validationPipeline,
        logger: logger
      )
      let server = try await factory(transport)
      self.statelessTransport = transport
      self.statelessServer = server
    }

    let channel = try await bootstrap.bind(
      host: configuration.host,
      port: configuration.port
    ).get()
    self.channel = channel

    if case .stateful = mode {
      Task { await sessionCleanupLoop() }
    }

    try await channel.closeFuture.get()
  }

  func stop() async {
    await closeAllSessions()

    if let transport = statelessTransport {
      await transport.disconnect()
      statelessTransport = nil
      statelessServer = nil
    }

    try? await channel?.close()
    channel = nil
    logger.info("FastMCP HTTP server stopped")
  }

  var endpoint: String { configuration.endpoint }

  func handleHTTPRequest(_ request: HTTPRequest) async -> HTTPResponse {
    switch mode {
    case .stateful:
      return await handleStatefulRequest(request)
    case .stateless:
      return await handleStatelessRequest(request)
    }
  }

  private func handleStatefulRequest(_ request: HTTPRequest) async -> HTTPResponse {
    let sessionID = request.header(HTTPHeaderName.sessionID)

    if let sessionID, var session = sessions[sessionID] {
      session.lastAccessedAt = Date()
      sessions[sessionID] = session

      let response = await session.transport.handleRequest(request)

      if request.method.uppercased() == "DELETE" && response.statusCode == 200 {
        sessions.removeValue(forKey: sessionID)
      }

      return response
    }

    if request.method.uppercased() == "POST",
      let body = request.body,
      Self.isInitializeRequest(body)
    {
      return await createSessionAndHandle(request)
    }

    if sessionID != nil {
      return .error(statusCode: 404, .invalidRequest("Not Found: Session not found or expired"))
    }
    return .error(
      statusCode: 400,
      .invalidRequest("Bad Request: Missing \(HTTPHeaderName.sessionID) header")
    )
  }

  private func handleStatelessRequest(_ request: HTTPRequest) async -> HTTPResponse {
    guard let transport = statelessTransport else {
      return .error(
        statusCode: 500,
        .internalError("Stateless transport not initialized")
      )
    }

    return await transport.handleRequest(request)
  }

  private struct FixedSessionIDGenerator: SessionIDGenerator {
    let sessionID: String
    func generateSessionID() -> String { sessionID }
  }

  private func createSessionAndHandle(_ request: HTTPRequest) async -> HTTPResponse {
    guard case .stateful(let factory) = mode else {
      return .error(
        statusCode: 500,
        .internalError("Session creation not available in stateless mode")
      )
    }

    let sessionID = UUID().uuidString

    let transport = StatefulHTTPServerTransport(
      sessionIDGenerator: FixedSessionIDGenerator(sessionID: sessionID),
      validationPipeline: validationPipeline,
      retryInterval: configuration.retryInterval,
      logger: logger
    )

    do {
      let server = try await factory(sessionID, transport)

      sessions[sessionID] = SessionContext(
        server: server,
        transport: transport,
        createdAt: Date(),
        lastAccessedAt: Date()
      )

      let response = await transport.handleRequest(request)

      if case .error = response {
        sessions.removeValue(forKey: sessionID)
        await transport.disconnect()
      }

      return response
    } catch {
      await transport.disconnect()
      return .error(
        statusCode: 500,
        .internalError("Failed to create session: \(error.localizedDescription)")
      )
    }
  }

  /// Uses raw JSON parsing because `JSONRPCMessageKind` is package-scoped in the upstream SDK.
  private static func isInitializeRequest(_ data: Data) -> Bool {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let method = json["method"] as? String
    else {
      return false
    }
    return method == "initialize"
  }

  private func closeSession(_ sessionID: String) async {
    guard let session = sessions.removeValue(forKey: sessionID) else { return }
    await session.transport.disconnect()
    logger.info("Closed session", metadata: ["sessionID": "\(sessionID)"])
  }

  private func closeAllSessions() async {
    for sessionID in sessions.keys {
      await closeSession(sessionID)
    }
  }

  private func sessionCleanupLoop() async {
    while true {
      try? await Task.sleep(for: .seconds(60))

      let now = Date()
      let expired = sessions.filter { _, context in
        now.timeIntervalSince(context.lastAccessedAt) > configuration.sessionTimeout
      }

      for (sessionID, _) in expired {
        logger.info("Session expired", metadata: ["sessionID": "\(sessionID)"])
        await closeSession(sessionID)
      }
    }
  }
}

/// NIO adapter: converts between NIO HTTP types and the framework-agnostic
/// `HTTPRequest`/`HTTPResponse` types, delegating all logic to `FastMCPHTTPServer`.
final class NIOHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
  typealias InboundIn = HTTPServerRequestPart
  typealias OutboundOut = HTTPServerResponsePart

  private let server: FastMCPHTTPServer

  private struct RequestState {
    var head: HTTPRequestHead
    var bodyBuffer: ByteBuffer
  }

  private var requestState: RequestState?

  init(server: FastMCPHTTPServer) {
    self.server = server
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let part = unwrapInboundIn(data)

    switch part {
    case .head(let head):
      requestState = RequestState(
        head: head,
        bodyBuffer: context.channel.allocator.buffer(capacity: 0)
      )
    case .body(var buffer):
      requestState?.bodyBuffer.writeBuffer(&buffer)
    case .end:
      guard let state = requestState else { return }
      requestState = nil

      nonisolated(unsafe) let ctx = context
      Task { @MainActor in
        await self.handleRequest(state: state, context: ctx)
      }
    }
  }

  private func handleRequest(
    state: RequestState,
    context: ChannelHandlerContext
  ) async {
    let head = state.head
    let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
    let endpoint = await server.endpoint

    guard path == endpoint else {
      await writeResponse(
        .error(statusCode: 404, .invalidRequest("Not Found")),
        version: head.version,
        context: context
      )
      return
    }

    let httpRequest = makeHTTPRequest(from: state)
    let response = await server.handleHTTPRequest(httpRequest)
    await writeResponse(response, version: head.version, context: context)
  }

  private func makeHTTPRequest(from state: RequestState) -> HTTPRequest {
    // Combine multiple header values per RFC 7230.
    var headers: [String: String] = [:]
    for (name, value) in state.head.headers {
      if let existing = headers[name] {
        headers[name] = existing + ", " + value
      } else {
        headers[name] = value
      }
    }

    let body: Data?
    if state.bodyBuffer.readableBytes > 0,
      let bytes = state.bodyBuffer.getBytes(at: 0, length: state.bodyBuffer.readableBytes)
    {
      body = Data(bytes)
    } else {
      body = nil
    }

    return HTTPRequest(
      method: state.head.method.rawValue,
      headers: headers,
      body: body
    )
  }

  private func writeResponse(
    _ response: HTTPResponse,
    version: HTTPVersion,
    context: ChannelHandlerContext
  ) async {
    nonisolated(unsafe) let ctx = context
    let eventLoop = ctx.eventLoop

    let statusCode = response.statusCode
    let headers = response.headers

    switch response {
    case .stream(let stream, _):
      eventLoop.execute {
        var head = HTTPResponseHead(
          version: version,
          status: HTTPResponseStatus(statusCode: statusCode)
        )
        for (name, value) in headers {
          head.headers.add(name: name, value: value)
        }
        ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)
        ctx.flush()
      }

      do {
        for try await chunk in stream {
          eventLoop.execute {
            var buffer = ctx.channel.allocator.buffer(capacity: chunk.count)
            buffer.writeBytes(chunk)
            ctx.writeAndFlush(
              self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
          }
        }
      } catch {
      }

      eventLoop.execute {
        ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      }

    default:
      let bodyData = response.bodyData
      eventLoop.execute {
        var head = HTTPResponseHead(
          version: version,
          status: HTTPResponseStatus(statusCode: statusCode)
        )
        for (name, value) in headers {
          head.headers.add(name: name, value: value)
        }

        ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)

        if let body = bodyData {
          var buffer = ctx.channel.allocator.buffer(capacity: body.count)
          buffer.writeBytes(body)
          ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }

        ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
      }
    }
  }
}
