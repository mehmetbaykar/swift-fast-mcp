// swift-fast-mcp — FastMCPAIBridge tests
// tools/list and related snapshots must follow registration order.

import FastMCPAIBridge
import SwiftAIHub
import Testing

// Selective MCP imports — full `import MCP` makes @Generable's `Prompt`
// ambiguous against `MCP.Prompt`.
import enum MCP.CallTool
import struct MCP.Tool
import enum MCP.Value

private struct NamedTool: SwiftAIHub.Tool {
  let name: String
  let description: String

  @Generable
  struct Arguments {}

  init(name: String) {
    self.name = name
    self.description = "tool \(name)"
  }

  func call(arguments: Arguments) async throws -> String { name }
}

private func proxied(
  serverName: String,
  name: String
) -> ProxiedMCPTool {
  ProxiedMCPTool(
    serverName: serverName,
    originalName: name,
    tool: MCP.Tool(
      name: name,
      description: "proxied \(name)",
      inputSchema: .object(["type": .string("object")])
    )
  ) { _, _ in CallTool.Result() }
}

@Suite("HubToolAdapter registration order")
struct HubToolAdapterRegistrationOrderTests {

  @Test
  func `listTools names and snapshot follow non-alphabetical registration order`() async throws {
    // Non-alphabetical registration order.
    let names = [
      "zeta", "alpha", "mike", "bravo", "yankee",
      "charlie", "xray", "delta", "whiskey", "echo",
      "victor", "foxtrot", "uniform", "golf", "tango",
      "hotel", "sierra", "india", "romeo", "juliet",
    ]
    #expect(names.count == 20)
    #expect(names != names.sorted())

    let adapter = try HubToolAdapter(tools: names.map { NamedTool(name: $0) })
    let listed1 = await adapter.listTools().map(\.name)
    let listed2 = await adapter.listTools().map(\.name)
    let nameList = await adapter.names()
    let snapshot = await adapter.snapshot().map(\.name)

    #expect(listed1 == names)
    #expect(listed2 == names)
    #expect(nameList == names)
    #expect(snapshot == names)
  }

  @Test
  func `unregister preserves order of remaining tools`() async throws {
    let adapter = try HubToolAdapter(
      tools: [
        NamedTool(name: "a"),
        NamedTool(name: "b"),
        NamedTool(name: "c"),
        NamedTool(name: "d"),
      ])
    await adapter.unregister(name: "b")
    let names = await adapter.names()
    let listed = await adapter.listTools().map(\.name)
    #expect(names == ["a", "c", "d"])
    #expect(listed == ["a", "c", "d"])
  }

  @Test
  func `unregisterProxiedTools preserves order of remaining entries`() async throws {
    let adapter = HubToolAdapter()
    try await adapter.register(NamedTool(name: "native1"))
    try await adapter.register(proxied(serverName: "srv", name: "p1"))
    try await adapter.register(NamedTool(name: "native2"))
    try await adapter.register(proxied(serverName: "srv", name: "p2"))
    try await adapter.register(NamedTool(name: "native3"))

    let removed = await adapter.unregisterProxiedTools(serverName: "srv")
    let names = await adapter.names()
    #expect(removed == 2)
    #expect(names == ["native1", "native2", "native3"])
  }

  @Test
  func `unregisterAllProxiedTools preserves native order`() async throws {
    let adapter = HubToolAdapter()
    try await adapter.register(NamedTool(name: "n1"))
    try await adapter.register(proxied(serverName: "a", name: "pa"))
    try await adapter.register(NamedTool(name: "n2"))
    try await adapter.register(proxied(serverName: "b", name: "pb"))

    let removed = await adapter.unregisterAllProxiedTools()
    let names = await adapter.names()
    #expect(removed == 2)
    #expect(names == ["n1", "n2"])
  }

  @Test
  func `replaceProxiedTools keeps position of first replaced tool`() async throws {
    let adapter = HubToolAdapter()
    try await adapter.register(NamedTool(name: "n1"))
    try await adapter.register(proxied(serverName: "docs", name: "old1"))
    try await adapter.register(proxied(serverName: "docs", name: "old2"))
    try await adapter.register(NamedTool(name: "n2"))

    try await adapter.replaceProxiedTools(
      serverName: "docs",
      with: [
        proxied(serverName: "docs", name: "new1"),
        proxied(serverName: "docs", name: "new2"),
        proxied(serverName: "docs", name: "new3"),
      ]
    )

    let names = await adapter.names()
    let proxiedNames = await adapter.proxiedTools(serverName: "docs").map(\.name)
    #expect(names == ["n1", "new1", "new2", "new3", "n2"])
    #expect(proxiedNames == ["new1", "new2", "new3"])
  }

  @Test
  func `replaceProxiedTools appends when server had no tools`() async throws {
    let adapter = try HubToolAdapter(tools: [NamedTool(name: "n1"), NamedTool(name: "n2")])
    try await adapter.replaceProxiedTools(
      serverName: "missing",
      with: [proxied(serverName: "missing", name: "p1")]
    )
    let names = await adapter.names()
    #expect(names == ["n1", "n2", "p1"])
  }

  @Test
  func `failed replaceProxiedTools leaves adapter unchanged`() async throws {
    let adapter = HubToolAdapter()
    try await adapter.register(NamedTool(name: "n1"))
    try await adapter.register(proxied(serverName: "docs", name: "old1"))
    try await adapter.register(NamedTool(name: "n2"))

    // Collision with existing native tool name must fail and roll back.
    await #expect(throws: HubBridgeError.self) {
      try await adapter.replaceProxiedTools(
        serverName: "docs",
        with: [proxied(serverName: "docs", name: "n1")]
      )
    }

    let names = await adapter.names()
    let proxiedNames = await adapter.proxiedTools(serverName: "docs").map(\.name)
    #expect(names == ["n1", "old1", "n2"])
    #expect(proxiedNames == ["old1"])
  }

  @Test
  func `register batch of proxied tools appends in given order`() async throws {
    let adapter = try HubToolAdapter(tools: [NamedTool(name: "n1")])
    try await adapter.register([
      proxied(serverName: "s", name: "p2"),
      proxied(serverName: "s", name: "p1"),
    ])
    let names = await adapter.names()
    let proxiedNames = await adapter.proxiedTools(serverName: "s").map(\.name)
    #expect(names == ["n1", "p2", "p1"])
    #expect(proxiedNames == ["p2", "p1"])
  }

  @Test
  func `failed proxied batch register leaves adapter unchanged`() async throws {
    let adapter = try HubToolAdapter(tools: [NamedTool(name: "n1")])
    await #expect(throws: HubBridgeError.self) {
      try await adapter.register([
        proxied(serverName: "s", name: "ok"),
        proxied(serverName: "s", name: "n1"),
      ])
    }
    let names = await adapter.names()
    #expect(names == ["n1"])
  }
}
