import FastMCP

@MCPResource(
  "config://app/settings",
  name: "App Settings",
  description: "Application configuration and feature flags",
  mimeType: "application/json"
)
public struct ConfigResource {
  @ResourceContentBuilder
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
}

@MCPResource(
  "system://info",
  name: "System Information",
  description: "Current system information",
  mimeType: "text/plain"
)
public struct SystemInfoResource {
  @ResourceContentBuilder
  public var content: Content {
    """
    OS: Ubuntu
    Architecture: x86_64
    Swift Version: 6.2
    """
  }
}
