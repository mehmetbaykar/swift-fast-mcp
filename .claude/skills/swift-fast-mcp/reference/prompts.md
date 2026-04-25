# `@MCPPrompt` Reference

Prompts in FastMCP are authored with `@MCPPrompt(_:name:)` and
`@PromptArgument(_:name:required:)`. The macros come from swift-fast-mcp
itself (`Sources/swift-fast-mcp/FastMCPMacros.swift`,
`Sources/FastMCPMacros/MCPPromptMacro.swift`,
`Sources/FastMCPMacros/PromptArgumentMacro.swift`). Full reference:
[`docs/PromptsResources.md`](../../../../docs/PromptsResources.md).

## Macro shape

```swift
@MCPPrompt("description", name: "optional_wire_name")
@PromptArgument("description", name: "optional_arg_name", required: true)
```

`@MCPPrompt` applies only to structs. It synthesises:

- `public var name: String`
- `public var description: String?`
- `public var arguments: [PromptArgumentSpec]`
- `public init()` (only when the struct has no user-declared init)
- `public func getMessages(arguments: [String: String]) async throws -> Messages`
- `extension … : MCPPrompt, Sendable`

When `name:` is omitted, the macro strips a trailing `Prompt` from the type
name and lowercases the first character. `GreetingPrompt` becomes
`greeting`.

The generated `getMessages(arguments:)` dispatcher decodes
`@PromptArgument` values out of the raw `[String: String]` payload, copies
them onto `self`, and calls a zero-argument `getMessages()` you declare.

## `@PromptArgument`

`@PromptArgument` is a peer marker macro — it emits no declarations.
`@MCPPrompt` reads its attribute values when building
`PromptArgumentSpec` entries.

The `required` flag in the spec is computed from:

1. Explicit `required:` argument when present.
2. Otherwise non-required when the property is optional or has a default.
3. Otherwise required.

Argument decoding by Swift type:

- `String` → raw value.
- `Bool` → `value.lowercased() == "true"`.
- `Int` / `Double` / `Float` → `T(value)`.
- Other base types → `T(rawValue: value)`, so custom prompt argument types
  must be string-backed raw-representable values.

Optionals receive the optional parse result. Required non-optional non-`String`
properties without defaults throw
`FastMCPError.missingRequiredPromptArgument(prompt:name:)` when missing
and `FastMCPError.invalidPromptArgumentValue(prompt:name:reason:)` when
unparseable.

## Canonical Example

From `Sources/ExampleTools/GreetingPrompt.swift`:

```swift
import FastMCP

@Generable
public enum GreetingTone: String, CaseIterable {
  case casual, formal, professional
}

@MCPPrompt("A friendly greeting conversation starter")
public struct GreetingPrompt {
  @PromptArgument("Who to greet", name: "name")
  public var who: String

  @PromptArgument("Tone to use")
  public var tone: GreetingTone = .casual

  public func getMessages() async throws -> Messages {
    switch tone {
    case .casual:
      return [
        .user("You are a friendly assistant helping \(who)."),
        .assistant("Hey \(who)! What can I help you with?"),
      ]
    case .formal:
      return [
        .user("You are a formal assistant helping \(who)."),
        .assistant("Good day, \(who). How may I assist you today?"),
      ]
    case .professional:
      return [
        .user("You are a professional assistant helping \(who)."),
        .assistant("Hello \(who), how can I help you today?"),
      ]
    }
  }
}
```

The `name:` override on the first `@PromptArgument` changes the public
argument name (`name`) without renaming the Swift property (`who`). The
`tone` argument has a default, so it lands in `prompts/list` without
`required: true`.

## `PromptMessage` factories

`PromptMessage` is `Sendable` and `ExpressibleByStringLiteral` (a string
literal becomes a `.user` text message). Static factories cover every
content type (`Sources/swift-fast-mcp/MCPPrompt.swift`):

- `.user(_:)` / `.assistant(_:)` — plain text.
- `.user(imageData:mimeType:)` / `.assistant(imageData:mimeType:)` — base64
  image payload plus MIME.
- `.user(audioData:mimeType:)` / `.assistant(audioData:mimeType:)` — base64
  audio payload plus MIME.
- `.user(resource:mimeType:text:blob:)` /
  `.assistant(resource:mimeType:text:blob:)` — embedded resource reference.

The role enum has exactly `.user` and `.assistant`. The content enum has
`.text(String)`, `.image(data:mimeType:)`, `.audio(data:mimeType:)`, and
`.resource(uri:mimeType:text:blob:)`.

## Registration

```swift
try await FastMCP.builder()
  .addPrompts([GreetingPrompt(), CodeReviewPrompt()])
  .run()
```

`addPrompts(_:)` accumulates across calls. Duplicates by `name` are
silently dropped; first registration wins.
