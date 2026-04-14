# @Schemable Macro Guide

The `@Schemable` macro (from MCPToolkit) automatically generates JSON Schema from Swift types. It's used on `Parameters` structs in MCPTool and `Arguments` structs in MCPPrompt.

## Basic Struct

```swift
@Schemable
public struct Parameters: Sendable {
  public let name: String
  public let age: Int
  public let score: Double
  public let active: Bool

  public init(name: String, age: Int, score: Double, active: Bool) {
    self.name = name
    self.age = age
    self.score = score
    self.active = active
  }
}
```

Supported primitive types: `String`, `Int`, `Double`, `Bool`.

## Optional Properties

Optional properties become optional in the generated JSON Schema (not in the `required` array):

```swift
@Schemable
public struct Parameters: Sendable {
  public let location: String        // required
  public let unit: TemperatureUnit?  // optional

  public init(location: String, unit: TemperatureUnit? = nil) {
    self.location = location
    self.unit = unit
  }
}
```

## Enum Parameters

Enums must have `String` raw values and be annotated with `@Schemable`:

```swift
@Schemable
public enum Operation: String, Sendable {
  case add
  case subtract
  case multiply
  case divide
}
```

The raw string values become the enum values in the JSON Schema.

Use enums as parameter types:

```swift
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
```

## Array Parameters

```swift
@Schemable
public struct Parameters: Sendable {
  public let items: [String]

  public init(items: [String]) {
    self.items = items
  }
}
```

## Doc Comments as Descriptions

Doc comments on properties become `description` fields in the generated JSON Schema:

```swift
@Schemable
public struct Arguments {
  /// Name of the person to greet
  public let name: String
  /// Use formal greeting style (optional, defaults to casual)
  public let formal: Bool?

  public init(name: String, formal: Bool? = nil) {
    self.name = name
    self.formal = formal
  }
}
```

## Required public init()

For cross-module access (library target -> executable target), all `@Schemable` types need an explicit `public init()`:

```swift
@Schemable
public struct Parameters: Sendable {
  public let query: String

  // Required for cross-module access
  public init(query: String) {
    self.query = query
  }
}
```

## Key Rules

- Always add `@Schemable` to both structs and enums used as parameters
- Enums must have `String` raw values
- Structs used as MCPTool Parameters must conform to `Sendable`
- Include `public init()` with all parameters for cross-module usage
- Use `let` properties (not `var`) for immutable parameters
- Optional properties use `?` suffix and have default `nil` in init
