# MCPTool Reference

## Protocol

```swift
public protocol MCPTool: Sendable {
  associatedtype Parameters: Decodable & Sendable
  var name: String { get }
  var description: String? { get }
  func call(with arguments: Parameters) async throws(ToolError) -> Content
}
```

- `Content` is a typealias for `[ToolContentItem]`
- Return value: `[ToolContentItem(text: "...")]`
- Typed throws: `throws(ToolError)` — only `ToolError` can be thrown

## Simple Tool

```swift
import FastMCP

public struct GreetingTool: MCPTool {
  public let name = "greet"
  public let description: String? = "Generate a greeting message"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let name: String
    public let formal: Bool?

    public init(name: String, formal: Bool? = nil) {
      self.name = name
      self.formal = formal
    }
  }

  public func call(with arguments: Parameters) async throws(ToolError) -> Content {
    let greeting =
      arguments.formal == true
      ? "Good day, \(arguments.name)."
      : "Hey \(arguments.name)!"
    return [ToolContentItem(text: greeting)]
  }
}
```

## Tool with Enum Parameters

```swift
import FastMCP

public struct MathTool: MCPTool {
  public let name = "calculate"
  public let description: String? = "Perform basic math operations"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let operation: Operation
    public let a: Double
    public let b: Double

    public init(operation: Operation, a: Double, b: Double) {
      self.operation = operation
      self.a = a
      self.b = b
    }
  }

  @Schemable
  public enum Operation: String, Sendable {
    case add
    case subtract
    case multiply
    case divide
  }

  public func call(with arguments: Parameters) async throws(ToolError) -> Content {
    let result: Double =
      switch arguments.operation {
      case .add: arguments.a + arguments.b
      case .subtract: arguments.a - arguments.b
      case .multiply: arguments.a * arguments.b
      case .divide:
        if arguments.b == 0 {
          throw ToolError("Division by zero")
        } else {
          arguments.a / arguments.b
        }
      }
    return [ToolContentItem(text: "Result: \(result)")]
  }
}
```

## Tool with Optional Parameters

```swift
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
    let temp = unit == .celsius ? "22C" : "72F"
    return [ToolContentItem(text: "Weather in \(arguments.location): \(temp), Sunny")]
  }
}
```

## Error Handling

Use typed throws with `ToolError`:

```swift
// Simple string error
throw ToolError("Division by zero")
```

`ToolError` wraps the error message and the MCPTool protocol converts it into an error response with `isError: true`.

## Registration

```swift
try await FastMCP.builder()
  .addTools([
    GreetingTool(),
    MathTool(),
    WeatherTool(),
  ])
  .run()
```

Multiple `.addTools()` calls accumulate tools. Duplicates (same `name`) are silently dropped — first registration wins.

## Key Requirements

- Parameters struct must be annotated with `@Schemable`
- Parameters struct must conform to `Sendable`
- Parameters struct needs `public init()` for cross-module access
- Tool struct needs `public init() {}`
- `name` and `description` are `let` properties
- `description` type is `String?`
- Enum parameters need `@Schemable` and `String` raw values
