import FastMCP

@Generable
public struct Coordinate {
  @Guide(description: "Latitude in decimal degrees, -90 to 90")
  public var latitude: Double

  @Guide(description: "Longitude in decimal degrees, -180 to 180")
  public var longitude: Double
}

@Generable
public enum TemperatureUnit: String, CaseIterable {
  case celsius, fahrenheit
}

@Tool("Get current weather for a location")
public struct WeatherTool {
  @Parameter("Location coordinates")
  public var coordinate: Coordinate = Coordinate(latitude: 0, longitude: 0)

  @Parameter("Temperature unit")
  public var unit: TemperatureUnit = .celsius

  public func execute() async throws -> String {
    let temp: String
    switch unit {
    case .celsius: temp = "22°C"
    case .fahrenheit: temp = "72°F"
    }
    return "Weather at (\(coordinate.latitude), \(coordinate.longitude)): \(temp), Sunny"
  }
}
