import Foundation
import Logging
import MCP
import ServiceLifecycle

struct FastMCPService: Service, Sendable {
  let server: Server
  let transport: MCP.Transport
  let logger: Logger
  let onStart: (@Sendable () async -> Void)?
  let onShutdown: (@Sendable () async -> Void)?

  func run() async throws {
    logger.info("Starting FastMCP server")

    if let onStart {
      await onStart()
    }

    try await server.start(transport: transport)
    logger.info("FastMCP server started")

    await server.waitUntilCompleted()

    if let onShutdown {
      await onShutdown()
    }

    logger.info("FastMCP server stopped")
  }
}
