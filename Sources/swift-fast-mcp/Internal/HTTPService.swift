import Foundation
import Logging
import ServiceLifecycle

/// `Service` wrapper so the HTTP transport joins the same `ServiceGroup`
/// shutdown-signal pipeline as the stdio/in-memory transports: `onStart` ->
/// run server -> on graceful shutdown stop the server -> `onShutdown`.
struct HTTPFastMCPService: Service, Sendable {
  let httpServer: FastMCPHTTPServer
  let logger: Logger
  let onStart: (@Sendable () async -> Void)?
  let onShutdown: (@Sendable () async -> Void)?

  func run() async throws {
    if let onStart {
      await onStart()
    }

    try await withGracefulShutdownHandler {
      try await httpServer.start()
    } onGracefulShutdown: {
      Task { await httpServer.stop() }
    }

    if let onShutdown {
      await onShutdown()
    }
  }
}
