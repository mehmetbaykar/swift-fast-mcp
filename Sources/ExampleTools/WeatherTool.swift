import FastMCP

@Tool("Get current weather for a location")
public struct WeatherTool {
  @Parameter("Location to look up")
  public var location: String

  @Parameter("Temperature unit", default: "celsius", oneOf: ["celsius", "fahrenheit"])
  public var unit: String = "celsius"

  public func execute() async throws -> String {
    let temp = unit == "celsius" ? "22°C" : "72°F"
    return "Weather in \(location): \(temp), Sunny"
  }
}
