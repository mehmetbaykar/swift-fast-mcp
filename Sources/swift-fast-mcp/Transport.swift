import Foundation
import MCP

public enum Transport: Sendable {
  case stdio
  case inMemory
  case custom(MCP.Transport)
}
