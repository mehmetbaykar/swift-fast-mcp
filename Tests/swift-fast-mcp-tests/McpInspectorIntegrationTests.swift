// End-to-end test that drives the Example stdio server via the official
// @modelcontextprotocol/inspector CLI. This is the only test that exercises
// the full MCP wire protocol against a real client — OnlineSearchIntegrationTests
// and the other integration tests run in-process.
//
// Gated on MCP_INSPECTOR_E2E=1 because it requires Node.js (npx) and builds
// the Example executable. CI flips the env var in .github/workflows/e2e.yml.
//
// Layer A (inspector-based) chosen because node is available in CI, the
// inspector CLI emits clean JSON to stdout, and keeping a real Node client
// in the loop catches breakage that a Swift-only JSON-RPC smoke would miss
// (framing bugs, protocol version negotiation drift, etc.).

import Foundation
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite("MCP Inspector E2E")
struct McpInspectorIntegrationTests {

  // MARK: - Gate

  private static var isEnabled: Bool {
    ProcessInfo.processInfo.environment["MCP_INSPECTOR_E2E"] == "1"
  }

  // MARK: - Helpers

  /// Resolves the Example binary path by running `swift build --product Example`
  /// and then `swift build --show-bin-path`, so the inspector spawns a prebuilt
  /// executable. Using `swift run` would race with the inspector's stdio framing
  /// (build output would leak into the JSON-RPC stream).
  private static func buildExampleBinary() throws -> URL {
    try runSwift(["build", "--product", "Example"])
    let binPath = try runSwift(["build", "--show-bin-path"]).trimmingCharacters(
      in: .whitespacesAndNewlines)
    let binary = URL(fileURLWithPath: binPath).appendingPathComponent("Example")
    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
      throw E2EError(
        "Example binary not found or not executable at \(binary.path). "
          + "Run `swift build --product Example` manually to reproduce.")
    }
    return binary
  }

  @discardableResult
  private static func runSwift(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift"] + arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let out =
      String(
        data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err =
      String(
        data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw E2EError(
        "swift \(arguments.joined(separator: " ")) exited \(process.terminationStatus)\n"
          + "stdout:\n\(out)\nstderr:\n\(err)")
    }
    return out
  }

  /// Invokes `npx --yes @modelcontextprotocol/inspector --cli …` against the
  /// given MCP server binary. Returns the raw stdout (which is JSON).
  private static func runInspector(
    binary: URL,
    method: String,
    extraArgs: [String] = []
  ) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var args = [
      "npx", "--yes", "@modelcontextprotocol/inspector",
      "--cli", "--transport", "stdio",
      binary.path,
      "--method", method,
    ]
    args.append(contentsOf: extraArgs)
    process.arguments = args
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let out =
      String(
        data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err =
      String(
        data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
      throw E2EError(
        "inspector exited \(process.terminationStatus) for method \(method)\n"
          + "stdout:\n\(out)\nstderr:\n\(err)")
    }
    return out
  }

  private struct E2EError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { self.description = message }
  }

  // MARK: - Tests

  @Test(
    "tools/list returns the four Example tools",
    .enabled(if: McpInspectorIntegrationTests.isEnabled))
  func listToolsMatchesExampleServer() throws {
    let binary = try Self.buildExampleBinary()
    let raw = try Self.runInspector(binary: binary, method: "tools/list")

    let data = Data(raw.utf8)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let tools = json?["tools"] as? [[String: Any]] ?? []
    let names = Set(tools.compactMap { $0["name"] as? String })

    #expect(
      names == ["math", "greeting", "weather", "structuredSearch"],
      "Expected exactly the four ExampleServer tools, got \(names). Raw:\n\(raw)")
  }

  @Test(
    "tools/call math add returns deterministic result",
    .enabled(if: McpInspectorIntegrationTests.isEnabled))
  func callMathAddReturnsExpectedResult() throws {
    let binary = try Self.buildExampleBinary()
    let raw = try Self.runInspector(
      binary: binary,
      method: "tools/call",
      extraArgs: [
        "--tool-name", "math",
        "--tool-arg", "operation=add",
        "--tool-arg", "a=2",
        "--tool-arg", "b=3",
      ])

    let data = Data(raw.utf8)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    let isError = (json?["isError"] as? Bool) ?? true
    #expect(isError == false, "Expected isError=false, got raw:\n\(raw)")

    let content = json?["content"] as? [[String: Any]] ?? []
    let firstText = (content.first?["text"] as? String) ?? ""
    // MathTool returns `"Result: 5.0"` as a Swift String; the FastMCP bridge
    // encodes that as a JSON string, so the outer quotes are part of the text
    // payload. We assert a substring to stay resilient to future formatting.
    #expect(
      firstText.contains("Result: 5"),
      "Expected math result payload to contain 'Result: 5', got raw:\n\(raw)")
  }
}
