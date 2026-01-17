import FastMCP

public struct ConfigResource: MCPResource {
  public let uri: String
  public let name: String
  public let description: String?
  public let mimeType: String?

  public var content: Content {
    """
    {
      "version": "1.0.0",
      "environment": "development",
      "features": {
        "darkMode": true,
        "notifications": true
      }
    }
    """
  }

  public init() {
    self.uri = "config://app/settings"
    self.name = "App Settings"
    self.description = "Application configuration and feature flags"
    self.mimeType = "application/json"
  }
}

public struct SystemInfoResource: MCPResource {
  public let uri: String
  public let name: String
  public let description: String?
  public let mimeType: String?

  public var content: Content {
    """
    OS: Ubuntu
    Architecture: x86_64
    Swift Version: 6.2
    """
  }

  public init() {
    self.uri = "system://info"
    self.name = "System Information"
    self.description = "Current system information"
    self.mimeType = "text/plain"
  }
}
