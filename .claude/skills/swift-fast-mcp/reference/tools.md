# `@Tool` Reference

Tools in FastMCP are authored with the `@Tool` macro from swift-ai-hub
(re-exported by `import FastMCP`). The macro turns a plain struct into a
`SwiftAIHub.Tool` and routes invocations through your `execute` method.
Pass instances to `FastMCP.builder().addTools([...])` to expose them on
`tools/list` / `tools/call`.

The macro contract is documented in `../swift-ai-hub/docs/Macros.md`.
The implementation is in
`../swift-ai-hub/Sources/SwiftAIHubMacros/ToolMacro.swift` and
`../swift-ai-hub/Sources/SwiftAIHub/Tools/ToolMacros.swift`.
The MCP wire shape is documented in
[`docs/Tools.md`](../../../../docs/Tools.md).

## Shape

Flat form:

```swift
@Tool("description")
public struct MyTool {
  @Parameter("…") public var x: T = defaultValue

  public func execute() async throws -> Output { … }
}
```

Nested form:

```swift
@Tool("description")
public struct MyTool {
  @Generable
  public struct Arguments {
    @Parameter("…") public var x: T
  }

  public func execute(_ arguments: Arguments) async throws -> Output { … }
}
```

Rules enforced by `@Tool`:

- The annotated type must be a `struct`.
- It can use flat `@Parameter` stored properties and `execute()`, or the nested
  `@Generable struct Arguments` form with `execute(_:)`.
- `Output` is inferred from the `execute` signature; it must satisfy
  `PromptRepresentable`.
- The description must be a string literal.
- Plain stored properties on the tool struct are allowed for dependencies;
  the macro synthesizes `init()` only when no user initializer exists and all
  stored properties can be initialized by an empty initializer.

Derived values:

| From | Rule |
|---|---|
| Wire `name` | Type name with a trailing `Tool` stripped, first letter lowercased. `WeatherTool` → `weather`. |
| Wire `description` | The macro's string argument. |
| `inputSchema` | Generated from flat `@Parameter` properties or nested `Arguments` by `@Generable`. |
| `Output` | Inferred from `execute`. |

The current `@Tool` macro has no `name:` argument and emits `name` from
`Self.schema.name`. Rename the Swift type when the wire name needs to change.

Plain stored properties on the tool struct that are neither flat `@Parameter`
fields nor part of the nested `Arguments` type are treated as init-injected
dependencies and stay invisible to the model.

## Canonical Example

From `Sources/ExampleTools/WeatherTool.swift`:

```swift
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
```

`tools/list` publishes a fully-dereferenced JSON Schema for `Arguments`
(nested `Coordinate` is inlined, `TemperatureUnit` is `string` + `enum`).
The exact wire payload is shown in `docs/Tools.md`.

## Returning Content

The shape of `execute`'s return type drives the wire shape:

- **`String`** — single `text` content block whose payload is the JSON-encoded
  string (because `String` conforms to `Generable`).
- **A `@Generable` struct or enum** — single `text` content block whose payload
  is `GeneratedContent.jsonString`.
- **Anything else `PromptRepresentable`** — single `text` content block
  containing `output.promptRepresentation.description`.

Structured output is just a `@Generable` return type; no separate protocol
or wrapper exists. Tools that need to emit images can override the hub-level
`makeOutputSegments(from:)` (see `docs/Tools.md`).

## Errors

`execute` uses plain `throws`, not typed throws. Any `Error` is caught by
the bridge and wrapped as `HubBridgeError.invalidArguments(tool:reason:)`,
which becomes a wire-level `isError: true` result with a `.text` content
block carrying `"Invalid arguments for <tool>: <reason>"`. From
`Sources/ExampleTools/MathTool.swift`:

```swift
public struct CalculationError: Error, CustomStringConvertible {
  public let description: String
}

public func execute(_ arguments: Arguments) async throws -> String {
  guard arguments.b != 0 else { throw CalculationError(description: "Division by zero") }
  …
}
```

The connection stays up; only the call result is marked as an error.

## Registration

```swift
try await FastMCP.builder()
  .addTools([WeatherTool(), MathTool(), StructuredSearchTool()])
  .run()
```

`addTools(_:)` is `throws` and
fails fast on duplicate tool names with
`HubBridgeError.duplicateTool(name:)`. The same check fires inside
`HubToolAdapter`, so a duplicate wire name is always a registration-time
failure, never a silent overwrite.

## Property Modifiers

For model-visible parameters, decorate flat tool properties or nested
`Arguments` properties with `@Parameter("…")` for the schema description, or
`@Guide(description: "…", …)` for descriptions plus
constraints. The accepted constraints (`.minimum`, `.maximum`, `.range`,
`.minimumCount`, `.maximumCount`, `.count`, `.constant`, `.anyOf`, `.pattern`)
are listed in `../swift-ai-hub/docs/Macros.md`. Optional properties (`T?`) and
properties with default values become non-required in the schema.
