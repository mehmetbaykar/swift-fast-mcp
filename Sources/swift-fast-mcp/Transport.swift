import Foundation
import MCP

public enum HTTPMode: Sendable {
  /// Full MCP Streamable HTTP: session management, SSE streaming, resumability, GET/DELETE support.
  case stateful

  /// No sessions, direct JSON responses, POST only.
  case stateless
}

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
