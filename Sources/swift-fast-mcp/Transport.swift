import Foundation

public enum Transport: Sendable {
  case stdio
  case http(port: Int)
}
