// swift-fast-mcp — FastMCPAIBridge tests
//
// Audit-D MISSING #2 coverage: prove a single `@Tool` instance works
// dual-use — registered once in a `LanguageModelSession` and once in a
// `HubToolAdapter`, both surfaces must dispatch to the same underlying
// object and project the same schema.
//
// The existing suite covers each surface in isolation:
//   * OnlineSearchIntegrationTests.swift — in-process `tool.execute(...)`
//     against a mocked provider.
//   * HubToolMapperSchemaTests.swift — schema projection only.
//   * HubToolAdapterImageTests.swift — adapter content mapping only.
//
// What's new here: the LITERAL shared tool value is the thing under test.
// EchoTool is a struct (Tool must be Sendable), but it carries a reference-
// typed `CallRecorder` so both surfaces write to the same slot. If either
// surface short-circuited and called a different object, the recorder would
// miss its entry and the parity assertions would fail.

import FastMCP
import FastMCPAIBridge
import Foundation
import SwiftAIHub
import Testing

import struct MCP.Tool
import enum MCP.Value

// MARK: - Shared fixtures

/// Reference-typed side-channel so tests can observe that both registration
/// surfaces end up invoking the SAME EchoTool value (same embedded recorder),
/// not two independently-constructed copies that happen to have equal state.
private final class CallRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String] = []

  func record(_ entry: String) {
    lock.lock()
    defer { lock.unlock() }
    entries.append(entry)
  }

  func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return entries
  }
}

/// Minimal @Tool used to prove dual-use. Name resolves to "echo" (the macro
/// strips the "Tool" suffix and lowercases the first letter).
@Tool("Echo back the input text for dual-use parity tests.")
private struct EchoTool {
  let recorder: CallRecorder

  @Generable
  struct Arguments {
    @Parameter("The text to echo back.")
    var text: String
  }

  init(recorder: CallRecorder) {
    self.recorder = recorder
  }

  func execute(_ arguments: Arguments) async throws -> String {
    recorder.record(arguments.text)
    return "echo: \(arguments.text)"
  }
}

/// Tool that rejects empty input — used for Test 3 (error parity).
@Tool("Rejects empty input for error-parity tests.")
private struct StrictEchoTool {
  enum StrictError: Error, Equatable {
    case empty
  }

  @Generable
  struct Arguments {
    @Parameter("Text — must be non-empty.")
    var text: String
  }

  func execute(_ arguments: Arguments) async throws -> String {
    if arguments.text.isEmpty {
      throw StrictError.empty
    }
    return "strict: \(arguments.text)"
  }
}

/// Unused stub model — LanguageModelSession requires `any LanguageModel`, but
/// these tests never drive `session.respond(to:)`. They inspect
/// `session.tools` and call the tool directly to exercise the in-process
/// surface without bringing a provider into the picture.
private struct UnusedStubModel: LanguageModel {
  typealias UnavailableReason = Never

  func respond<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions
  ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
    fatalError("UnusedStubModel.respond must not be invoked by dual-registration tests")
  }

  func streamResponse<Content>(
    within session: LanguageModelSession,
    to prompt: Prompt,
    generating type: Content.Type,
    includeSchemaInPrompt: Bool,
    options: GenerationOptions
  ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
    fatalError("UnusedStubModel.streamResponse must not be invoked by dual-registration tests")
  }
}

// MARK: - Helpers

/// Resolves the top-level `$ref` of an encoded `GenerationSchema` against its
/// `$defs` table and returns the referenced object dictionary. This mirrors
/// what `HubToolMapper.inputSchema(for:)` does internally — encoding a
/// `GenerationSchema` to JSON yields `{"$defs": {...}, "$ref": "#/$defs/X"}`,
/// so `properties`/`required` live one level down inside `$defs`.
private func resolveRootObject(fromJSON data: Data) throws -> [String: Any] {
  guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    return [:]
  }
  // Inline root (no $ref): return as-is.
  if root["$ref"] == nil {
    return root
  }
  guard
    let ref = root["$ref"] as? String,
    let defs = root["$defs"] as? [String: Any]
  else {
    return [:]
  }
  let key = ref.replacingOccurrences(of: "#/$defs/", with: "")
  return (defs[key] as? [String: Any]) ?? [:]
}

private func propertyNames(fromJSON data: Data) throws -> Set<String> {
  let object = try resolveRootObject(fromJSON: data)
  guard let properties = object["properties"] as? [String: Any] else { return [] }
  return Set(properties.keys)
}

private func requiredNames(fromJSON data: Data) throws -> Set<String> {
  let object = try resolveRootObject(fromJSON: data)
  guard let required = object["required"] as? [String] else { return [] }
  return Set(required)
}

private func propertyNames(fromMCP schema: Value) -> Set<String> {
  guard
    case .object(let root) = schema,
    case .object(let properties) = root["properties"] ?? .null
  else {
    return []
  }
  return Set(properties.keys)
}

private func requiredNames(fromMCP schema: Value) -> Set<String> {
  guard
    case .object(let root) = schema,
    case .array(let required) = root["required"] ?? .null
  else {
    return []
  }
  var names: Set<String> = []
  for entry in required {
    if case .string(let name) = entry {
      names.insert(name)
    }
  }
  return names
}

// MARK: - Tests

@Suite("Dual registration: one @Tool instance, both surfaces")
struct DualRegistrationTests {

  // Test 1 — Same @Tool value serves both surfaces for identical input.
  //
  // Register ONE EchoTool in both a HubToolAdapter (MCP wire path) and a
  // LanguageModelSession (in-process path). Drive the MCP path via
  // `adapter.makeContent(name:arguments:)` and the in-process path via the
  // tool that LanguageModelSession actually holds (`session.tools.first`),
  // exercising the same `makeOutputSegments` entry point the session's own
  // tool-call loop uses. Both surfaces are fed the SAME input; the shared
  // CallRecorder confirms each call landed on the EchoTool value the caller
  // passed in (not an independent copy), and the decoded MCP payload is
  // compared directly to the in-process output for cross-surface equality.
  //
  // Struct tools are value types — there is no object identity to assert —
  // so the practical proof is that both copies share the same embedded
  // reference-typed dependency (CallRecorder) and produce equal output.
  @Test
  func `MCP and in-process paths dispatch the same registered @Tool`() async throws {
    let recorder = CallRecorder()
    let echoTool = EchoTool(recorder: recorder)

    // Register ONCE in the MCP bridge.
    let adapter = HubToolAdapter()
    try await adapter.register(echoTool)

    // Register the same tool value in a LanguageModelSession.
    let session = LanguageModelSession(
      model: UnusedStubModel(),
      tools: [echoTool],
      instructions: "Unused for this test."
    )

    // Pre-checks: both surfaces expose the tool under the macro-derived name.
    let adapterNames = await adapter.names()
    #expect(adapterNames == ["echo"], "adapter should expose exactly 'echo'")

    let sessionNames = session.tools.map { $0.name }
    #expect(sessionNames == ["echo"], "session should expose exactly 'echo'")

    // Same input drives both surfaces so outputs are directly comparable.
    let sharedInput = "shared-input"
    let arguments = MCP.Value.object(["text": .string(sharedInput)])

    // --- MCP surface ---
    //
    // `makeContent` routes a String-returning tool through the default
    // `Tool.makeOutputSegments` implementation, which wraps String output as
    // a `.structure` segment (String conforms to ConvertibleToGeneratedContent).
    // `HubToolAdapter.toolContent(from:)` then serializes the structure to
    // JSON text. The emitted `.text` payload is therefore the JSON-encoded
    // form of the raw in-process String — same semantic content, different
    // wire framing. See HubToolAdapterImageTests `structuredOutputFallsBackToJSONText`
    // for the matching direct coverage.
    let mcpContent = try await adapter.makeContent(name: "echo", arguments: arguments)
    #expect(mcpContent.count == 1)
    guard case .text(let mcpText, _, _) = mcpContent.first else {
      Issue.record("Expected .text MCP content, got \(String(describing: mcpContent.first))")
      return
    }
    let mcpPayload = try JSONDecoder().decode(String.self, from: Data(mcpText.utf8))

    // --- In-process surface ---
    //
    // Pull the tool out of `session.tools` — this is the exact value the
    // session's own tool-call loop dispatches to — and invoke its
    // `makeOutputSegments` with the same arguments. This proves the session
    // registration path, not just the local `echoTool` binding.
    guard let sessionTool = session.tools.first else {
      Issue.record("session.tools should contain the registered EchoTool")
      return
    }
    let inProcessSegments = try await sessionTool.makeOutputSegments(
      from: HubValueMapper.generatedContent(from: arguments)
    )
    #expect(inProcessSegments.count == 1)
    guard case .structure(let structure) = inProcessSegments.first else {
      Issue.record(
        "Expected .structure segment from default String dispatch, got \(String(describing: inProcessSegments.first))"
      )
      return
    }
    guard case .string(let inProcessPayload) = structure.content.kind else {
      Issue.record("Expected .string kind inside structure, got \(structure.content.kind)")
      return
    }

    // --- Cross-surface equality: identical input → identical payload ---
    #expect(
      mcpPayload == inProcessPayload,
      "MCP-decoded payload must equal session-dispatched output, got mcp=\(mcpPayload) inProcess=\(inProcessPayload)"
    )
    #expect(inProcessPayload == "echo: \(sharedInput)")

    // --- Recorder parity: both surfaces hit the shared side-channel ---
    // Two recorded entries for one shared input prove both registration
    // sites dispatched to an EchoTool holding the same CallRecorder reference.
    let recorded = recorder.snapshot()
    #expect(
      recorded == [sharedInput, sharedInput],
      "shared recorder should observe both calls, got \(recorded)"
    )
  }

  // Test 2 — Schema parity.
  //
  // The Tool protocol exposes `parameters: GenerationSchema`. The MCP surface
  // exposes `HubToolMapper.inputSchema(for:)`, which round-trips that same
  // schema through JSON (inlining $defs) into an MCP `Value`. Assert both
  // projections agree on the property list and required list.
  @Test
  func `Tool.parameters and HubToolMapper.inputSchema project the same property set`() throws {
    let recorder = CallRecorder()
    let echoTool = EchoTool(recorder: recorder)

    // Hub-side schema: encode Tool.parameters as JSON, parse property names.
    let hubSchemaJSON = try JSONEncoder().encode(echoTool.parameters)
    let hubProperties = try propertyNames(fromJSON: hubSchemaJSON)
    let hubRequired = try requiredNames(fromJSON: hubSchemaJSON)

    // MCP-side schema: project through the mapper.
    let mcpSchema = HubToolMapper.inputSchema(for: echoTool)
    let mcpProperties = propertyNames(fromMCP: mcpSchema)
    let mcpRequired = requiredNames(fromMCP: mcpSchema)

    // Parity — both sides must agree on what the tool accepts.
    #expect(
      hubProperties == mcpProperties,
      "property sets differ: hub=\(hubProperties) mcp=\(mcpProperties)")
    #expect(
      hubRequired == mcpRequired, "required sets differ: hub=\(hubRequired) mcp=\(mcpRequired)")

    // Anchor: the test tool declares exactly `text` as the sole required
    // property. This prevents the parity test from degenerating into a
    // tautology if both sides happened to emit empty schemas.
    #expect(hubProperties == ["text"], "EchoTool.Arguments should declare 'text' only")
    #expect(hubRequired == ["text"], "'text' should be required on the hub schema")

    // MCP schema must also be an object schema with an object-typed `text`
    // property — covers the mapper's shape projection, not just key parity.
    guard case .object(let mcpRoot) = mcpSchema else {
      Issue.record("MCP schema should be an object, got \(mcpSchema)")
      return
    }
    #expect(mcpRoot["type"] == .string("object"))
    guard case .object(let mcpProps) = mcpRoot["properties"] ?? .null,
      case .object(let textProp) = mcpProps["text"] ?? .null
    else {
      Issue.record("MCP schema missing 'text' property object")
      return
    }
    #expect(textProp["type"] == .string("string"))

    // Name + description on the MCP side must also round-trip from the Tool
    // protocol — otherwise the MCP client sees a different tool identity
    // than the session's in-process dispatch path.
    let mapped = HubToolMapper.mapTool(echoTool)
    #expect(mapped.name == echoTool.name)
    #expect(mapped.description == echoTool.description)
  }

  // Test 3 — Error parity (documented shape difference).
  //
  // A tool that throws for invalid input surfaces its error differently on
  // each surface:
  //   * MCP path: `HubToolAdapter.makeContent` wraps the thrown error in
  //     `HubBridgeError.invalidArguments(tool:reason:)`, and callers fold
  //     it to `CallTool.Result(isError: true, content: [.text(...)])` via
  //     `HubErrorMapper.mapCallToolError`.
  //   * In-process path: `tool.execute(_:)` throws the raw error directly
  //     — callers (or LanguageModelSession) wrap it further as they see
  //     fit.
  //
  // Both shapes are correct for their channel; this test pins the CURRENT
  // contract so a regression on either side is caught.
  @Test
  func `Tool errors surface correctly on both surfaces (with expected shape difference)`() async throws {
    let strictTool = StrictEchoTool()
    let adapter = try HubToolAdapter(tools: [strictTool])

    // --- MCP surface: thrown errors become HubBridgeError.invalidArguments ---
    let mcpError: Error
    do {
      _ = try await adapter.makeContent(
        name: "strictEcho",
        arguments: .object(["text": .string("")])
      )
      Issue.record("Expected HubBridgeError from MCP path on empty input")
      return
    } catch {
      mcpError = error
    }

    guard case HubBridgeError.invalidArguments(let toolName, let reason) = mcpError else {
      Issue.record("Expected HubBridgeError.invalidArguments, got \(mcpError)")
      return
    }
    #expect(toolName == "strictEcho")
    #expect(
      reason.contains("empty") || reason.contains("StrictError"),
      "reason should reference underlying error, got \(reason)"
    )

    // HubErrorMapper must fold that wrapping error into isError:true text.
    let callResult = HubErrorMapper.mapCallToolError(mcpError, toolName: "strictEcho")
    #expect(callResult.isError == true)
    #expect(callResult.content.count == 1)
    guard case .text(let errorText, _, _) = callResult.content.first else {
      Issue.record(
        "Expected .text error content, got \(String(describing: callResult.content.first))")
      return
    }
    #expect(errorText.contains("strictEcho"))

    // --- In-process surface: raw error bubbles out of execute(_:) ---
    do {
      _ = try await strictTool.execute(StrictEchoTool.Arguments(text: ""))
      Issue.record("Expected StrictError.empty from in-process path")
    } catch let raw as StrictEchoTool.StrictError {
      #expect(raw == .empty, "raw error should be StrictError.empty")
    } catch {
      Issue.record("Expected StrictError.empty, got \(error)")
    }

    // Shape difference documented:
    //   * MCP path wraps in HubBridgeError.invalidArguments THEN becomes
    //     CallTool.Result(isError: true).
    //   * In-process path throws the raw StrictError.empty directly.
    // Both behaviors are intentional and tested above.
  }
}
