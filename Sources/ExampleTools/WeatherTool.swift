import FastMCP

public struct WeatherTool: SwiftAIHub.Tool {
  public let name = "get_weather"
  public let description = "Get current weather for a location"

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Location to look up")
    public let location: String
    @Guide(description: "Temperature unit: celsius or fahrenheit")
    public let unit: String?
  }

  public init() {}

  public func call(arguments: Arguments) async throws -> String {
    let unit = arguments.unit ?? "celsius"
    let temp = unit == "celsius" ? "22°C" : "72°F"
    return "Weather in \(arguments.location): \(temp), Sunny"
  }
}
