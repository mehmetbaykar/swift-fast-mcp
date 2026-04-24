import Foundation

public enum FastMCPError: Error, LocalizedError, Sendable {
  case portInUse(Int)
  case invalidConfiguration(String)
  case authRequiredForHTTP
  case serverStartFailed(String)
  case missingRequiredPromptArgument(prompt: String, name: String)
  case invalidPromptArgumentValue(prompt: String, name: String, reason: String)
  case generic(Error)

  public var errorDescription: String? {
    switch self {
    case .portInUse(let port):
      return "Port \(port) is already in use"
    case .invalidConfiguration(let message):
      return "Invalid configuration: \(message)"
    case .authRequiredForHTTP:
      return "HTTP transport requires auth configuration for security"
    case .serverStartFailed(let message):
      return "Server failed to start: \(message)"
    case .missingRequiredPromptArgument(let prompt, let name):
      return "Prompt '\(prompt)' is missing required argument '\(name)'"
    case .invalidPromptArgumentValue(let prompt, let name, let reason):
      return "Prompt '\(prompt)' argument '\(name)' has invalid value: \(reason)"
    case .generic(let error):
      return "Unexpected error: \(error.localizedDescription)"
    }
  }
}
