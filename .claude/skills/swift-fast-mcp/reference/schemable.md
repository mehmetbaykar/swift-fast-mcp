# `@Generable` / `@Parameter` / `@Guide` Reference

Schemas in FastMCP come from swift-ai-hub's macros, re-exported through
`import FastMCP`. The full contract lives in
`../swift-ai-hub/docs/Macros.md`. Source declarations:
`../swift-ai-hub/Sources/SwiftAIHub/Generation/Generable.swift`,
`../swift-ai-hub/Sources/SwiftAIHub/Tools/ToolMacros.swift`, and
`../swift-ai-hub/Sources/SwiftAIHubMacros/ParameterMacro.swift`.

## When to use which

- `@Tool("description")` on the tool struct.
- `@Generable` on every type the model produces or consumes: the nested
  `Arguments` struct, any nested types it references, and any structured
  return type from `execute(_:)`.
- `@Parameter("description")` on stored properties of `Arguments`. It is a
  marker macro that supplies the schema description at the tool boundary.
- `@Guide(description:, …)` on stored properties of any `@Generable` type
  that needs a description plus constraints (numeric `.minimum` / `.maximum`
  / `.range`, array `.minimumCount` / `.maximumCount` / `.count`, string
  `.constant` / `.anyOf` / `.pattern`).

## Enums

Enums must declare a `String` raw value (the schema renders them as
`type: "string"` with `enum`):

```swift
@Generable
public enum TemperatureUnit: String, CaseIterable {
  case celsius, fahrenheit
}
```

## Optional and default-valued properties

A property typed `T?` becomes non-required in the schema. A property with a
default value also becomes non-required.

```swift
@Generable
public struct Person {
  @Guide(description: "First name") public var firstName: String
  @Guide(description: "Last name (optional)") public var lastName: String?
}
```

## Generated members

For a struct, `@Generable` adds `init(_:)`, `generatedContent`,
`generationSchema`, a memberwise initializer, prompt/instructions
representations, and a `PartiallyGenerated` mirror for streaming. For an
enum, it adds the same minus `PartiallyGenerated`. Conformances declared by
the macro: `Generable`, `Codable`. See `../swift-ai-hub/docs/Macros.md` for
the full expansion.
