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
  @Generable
  public struct Arguments {
    @Parameter("Location coordinates")
    public var coordinate: Coordinate

    @Parameter("Temperature unit")
    public var unit: TemperatureUnit
  }

  public func execute(_ arguments: Arguments) async throws -> String {
    let temp: String
    switch arguments.unit {
    case .celsius: temp = "22°C"
    case .fahrenheit: temp = "72°F"
    }
    return
      "Weather at (\(arguments.coordinate.latitude), \(arguments.coordinate.longitude)): \(temp), Sunny"
  }
}
