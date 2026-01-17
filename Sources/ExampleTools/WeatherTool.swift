import FastMCP

public struct WeatherTool: MCPTool {
  public let name = "get_weather"
  public let description: String? = "Get current weather for a location"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let location: String
    public let unit: TemperatureUnit?

    public init(location: String, unit: TemperatureUnit? = nil) {
      self.location = location
      self.unit = unit
    }
  }

  @Schemable
  public enum TemperatureUnit: String, Sendable {
    case celsius
    case fahrenheit
  }

  public func call(with arguments: Parameters) async throws(ToolError) -> Content {
    let unit = arguments.unit ?? .celsius
    let temp = unit == .celsius ? "22°C" : "72°F"
    return [ToolContentItem(text: "Weather in \(arguments.location): \(temp), Sunny")]
  }
}
