# Prompts and Resources

`swift-fast-mcp` provides macros and helper types for MCP prompts and
resources:

- `@MCPPrompt`
- `@PromptArgument`
- `@MCPResource`
- `@ResourceContentBuilder`

## `@MCPPrompt`

```swift
@attached(member, names: named(name), named(description), named(arguments), named(init), named(getMessages))
@attached(extension, conformances: MCPPrompt, Sendable)
public macro MCPPrompt(_ description: String, name: String? = nil)
```

Apply `@MCPPrompt("description")` to a struct. The implementation emits:

- `public var name: String`
- `public var description: String?`
- `public var arguments: [PromptArgumentSpec]`
- `public init()` when the struct does not declare an initializer
- `public func getMessages(arguments: [String: String]) async throws -> Messages`
- `extension Type: MCPPrompt, Swift.Sendable`

The description is required, and the macro applies only to structs. If `name:`
is omitted, the macro drops a trailing `Prompt` suffix from the type name and
lowercases the first character. `GreetingPrompt` becomes `greeting`.

The generated `getMessages(arguments:)` dispatcher copies `self`, decodes
`@PromptArgument` values from the raw `[String: String]` argument dictionary,
and calls the user-declared zero-argument `getMessages()`.

## `@PromptArgument`

```swift
@attached(peer)
public macro PromptArgument(
  _ description: String,
  name: String? = nil,
  required: Bool? = nil
)
```

`@PromptArgument` is a marker macro. Its peer expansion emits no declarations.
`@MCPPrompt` reads stored properties annotated with `@PromptArgument` and uses
their attribute values to build `PromptArgumentSpec` values.

The public argument name defaults to the property name. A `name:` override
changes only the public argument name, not the Swift property name.

The `required` value in `PromptArgumentSpec` is computed as follows:

1. Use explicit `required:` when present.
2. Otherwise, the argument is not required when the property is optional or has
   a default value.
3. Otherwise, the argument is required.

The dispatcher decodes values by base Swift type:

- `String`: uses the raw dictionary value.
- `Bool`: maps any present string to `value.lowercased() == "true"`.
- `Int`: parses with `Int(value)`.
- `Double`: parses with `Double(value)`.
- `Float`: parses with `Float(value)`.
- Any other base type: parses with `Type(rawValue: value)`.

Optional properties receive the optional parse result. That means optional
`String` is `nil` when missing, optional `Bool` is `nil` when missing and
`false` for any present value other than `"true"`, and optional numeric or
raw-value types are `nil` when missing or unparseable.

For required non-optional non-`String` properties without defaults, missing
values throw `FastMCPError.missingRequiredPromptArgument(prompt:name:)`, and
unparseable values throw
`FastMCPError.invalidPromptArgumentValue(prompt:name:reason:)`. For
non-optional non-`String` properties with defaults, missing values keep the
default and present-but-unparseable values throw. A non-optional `String`
requires a present raw value.

## Prompt Types

`MCPPrompt` declares:

```swift
typealias Messages = [PromptMessage]

var name: String { get }
var description: String? { get }
var arguments: [PromptArgumentSpec] { get }

func getMessages(arguments: [String: String]) async throws -> Messages
```

`PromptArgumentSpec` contains `name`, `description`, and `required`.

`PromptMessage` contains `role` and `content`. `PromptMessageRole` has exactly
these cases:

```swift
case user
case assistant
```

`PromptMessageContent` has exactly these cases:

```swift
case text(String)
case image(data: String, mimeType: String)
case audio(data: String, mimeType: String)
case resource(uri: String, mimeType: String, text: String?, blob: String?)
```

`PromptMessage` also provides `user` and `assistant` factory methods for text,
image, audio, and embedded resource content. A string literal creates a user
text message.

## Greeting Prompt Example

Exact `GreetingPrompt` excerpt from `Sources/ExampleTools/GreetingPrompt.swift`:

```swift
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

## `@MCPResource`

```swift
@attached(member, names: named(uri), named(name), named(description), named(mimeType), named(init))
@attached(extension, conformances: MCPResource, Sendable)
public macro MCPResource(
  _ uri: String,
  name: String? = nil,
  description: String? = nil,
  mimeType: MCPResourceMimeType? = nil
)
```

Apply `@MCPResource("uri")` to a struct. The implementation emits:

- `public var uri: String`
- `public var name: String?` only when `name:` is present
- `public var description: String?` only when `description:` is present
- `public var mimeType: String?` only when `mimeType:` resolves
- `public init()` when the struct does not declare an initializer
- `extension Type: MCPResource, Swift.Sendable`

The URI is required, and the macro applies only to structs. The macro does not
emit `content`; the struct must satisfy the `MCPResource` protocol by declaring
a resource content property.

```swift
@ResourceContentBuilder
public var content: Content { ... }
```

`MCPResource` declares `typealias Content = [ResourceContentItem]`.
`ResourceContentItem` stores either `.text(String)` or `.blob(String)` plus an
optional per-item MIME type. `ResourceContentBuilder` is
`ContentBuilder<ResourceContentItem>`.

## Config Resource Example

Exact `ConfigResource` source from `Sources/ExampleTools/ConfigResource.swift`:

```swift
import FastMCP

@MCPResource(
  "config://app/settings",
  name: "App Settings",
  description: "Application configuration and feature flags",
  mimeType: .applicationJSON
)
public struct ConfigResource {
  @ResourceContentBuilder
  public var content: Content {
    """
    {
      "version": "1.0.0",
      "environment": "development",
      "features": {
        "darkMode": true,
        "notifications": true
      }
    }
    """
  }
}
```

## `MCPResourceMimeType`

`MCPResourceMimeType` has exactly these cases and raw values:

| Case | `rawValue` |
| --- | --- |
| `.applicationJSON` | `"application/json"` |
| `.applicationXML` | `"application/xml"` |
| `.applicationOctetStream` | `"application/octet-stream"` |
| `.textPlain` | `"text/plain"` |
| `.textMarkdown` | `"text/markdown"` |
| `.textHTML` | `"text/html"` |
| `.textCSV` | `"text/csv"` |
| `.imagePNG` | `"image/png"` |
| `.imageJPEG` | `"image/jpeg"` |
| `.other(String)` | associated string value |

The enum is `Sendable`, `Hashable`, and `Codable`. It provides
`rawValue: String`, `init(_ rawValue: String)`, and single-value `Codable`
encoding/decoding through the raw string.

`@MCPResource` accepts bare-dot MIME cases such as `.applicationJSON` and maps
them to strings in the generated `mimeType` getter. It also accepts
`.other("...")` when the associated value is a string literal.

## Wire Shapes

These examples show method result payloads produced through the repo's
registrars and the MCP Swift SDK models.

`prompts/list` returns a `prompts` array. For `GreetingPrompt`, `tone` has a
default value, so FastMCP passes `required: nil` to the SDK model and the field
is omitted by normal `Codable` encoding:

```json
{
  "prompts": [
    {
      "name": "greeting",
      "description": "A friendly greeting conversation starter",
      "arguments": [
        { "name": "name", "description": "Who to greet", "required": true },
        { "name": "tone", "description": "Tone to use" }
      ]
    }
  ]
}
```

`prompts/get` returns `description` and `messages`:

```json
{
  "description": "A friendly greeting conversation starter",
  "messages": [
    {
      "role": "user",
      "content": { "type": "text", "text": "You are a friendly assistant helping Taylor." }
    },
    {
      "role": "assistant",
      "content": { "type": "text", "text": "Hey Taylor! What can I help you with?" }
    }
  ]
}
```

`resources/list` returns a `resources` array. For `ConfigResource`:

```json
{
  "resources": [
    {
      "name": "App Settings",
      "uri": "config://app/settings",
      "description": "Application configuration and feature flags",
      "mimeType": "application/json"
    }
  ]
}
```

`resources/read` returns `contents`. FastMCP maps per-item MIME types from
`ResourceContentItem`, not from the resource-level `mimeType`. The
`ConfigResource` string literal has no per-item MIME type, so its content item
does not include `mimeType`:

```json
{
  "contents": [
    {
      "uri": "config://app/settings",
      "text": "{\n  \"version\": \"1.0.0\",\n  \"environment\": \"development\",\n  \"features\": {\n    \"darkMode\": true,\n    \"notifications\": true\n  }\n}"
    }
  ]
}
```

Blob content uses `blob` instead of `text` and includes `mimeType` when the
content item supplies one.
