import ExampleTools
import FastMCPAIBridge
import MCP
import SwiftAIHub
import Testing

@testable import FastMCP

// Helpers to read hub tool state back out of a FastMCPServerHandle, which now
// stores tools inside a HubToolAdapter rather than a plain array.
extension FastMCPServerHandle {
  fileprivate func currentToolNames() async -> [String] {
    await currentToolAdapter.names()
  }

  fileprivate func seed(
    tools: [any SwiftAIHub.Tool] = [],
    resources: [any MCPResource] = [],
    prompts: [any MCPPrompt] = []
  ) throws {
    configure(
      toolAdapter: try HubToolAdapter(tools: tools),
      upstreamManager: nil,
      resources: resources,
      prompts: prompts
    )
  }
}

// MARK: - CapabilitiesBuilder listChanged Tests

@Suite("CapabilitiesBuilder listChanged")
struct CapabilitiesBuilderListChangedTests {

  @Test
  func `listChanged defaults to false`() {
    let capabilities = CapabilitiesBuilder.build(
      hasTools: true,
      hasResources: true,
      hasPrompts: true
    )

    #expect(capabilities.tools?.listChanged == false)
    #expect(capabilities.resources?.listChanged == false)
    #expect(capabilities.prompts?.listChanged == false)
  }

  @Test
  func `listChanged true is propagated to all capabilities`() {
    let capabilities = CapabilitiesBuilder.build(
      hasTools: true,
      hasResources: true,
      hasPrompts: true,
      listChanged: true
    )

    #expect(capabilities.tools?.listChanged == true)
    #expect(capabilities.resources?.listChanged == true)
    #expect(capabilities.prompts?.listChanged == true)
  }

  @Test
  func `listChanged true only applies to enabled capabilities`() {
    let capabilities = CapabilitiesBuilder.build(
      hasTools: true,
      hasResources: false,
      hasPrompts: false,
      listChanged: true
    )

    #expect(capabilities.tools?.listChanged == true)
    #expect(capabilities.resources == nil)
    #expect(capabilities.prompts == nil)
  }
}

// MARK: - Builder serverHandle Tests

@Suite("Builder serverHandle")
struct BuilderServerHandleTests {

  @Test
  func `serverHandle defaults to nil`() {
    let builder = FastMCP.builder()
    #expect(builder.handle == nil)
  }

  @Test
  func `serverHandle stores the handle`() {
    let handle = FastMCPServerHandle()
    let builder = FastMCP.builder().serverHandle(handle)
    #expect(builder.handle != nil)
  }

  @Test
  func `serverHandle preserves value semantics`() {
    let handle = FastMCPServerHandle()
    let original = FastMCP.builder()
    let modified = original.serverHandle(handle)

    #expect(original.handle == nil)
    #expect(modified.handle != nil)
  }

  @Test
  func `Builder chain works with serverHandle`() throws {
    let handle = FastMCPServerHandle()
    let builder = try FastMCP.builder()
      .name("Dynamic")
      .version("1.0.0")
      .addTools([WeatherTool()])
      .serverHandle(handle)
      .transport(.stdio)

    #expect(builder.serverName == "Dynamic")
    #expect(builder.hubTools.count == 1)
    #expect(builder.handle != nil)
  }
}

// MARK: - FastMCPServerHandle State Management Tests

@Suite("FastMCPServerHandle Tools")
struct ServerHandleToolTests {

  @Test
  func `starts with empty tools`() async {
    let handle = FastMCPServerHandle()
    let names = await handle.currentToolNames()
    #expect(names.isEmpty)
  }

  @Test
  func `configure seeds initial tools`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.seed(tools: [WeatherTool()])
    let names = await handle.currentToolNames()
    #expect(names == ["weather"])
  }

  @Test
  func `addTool appends a tool`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.addTool(WeatherTool())
    let names = await handle.currentToolNames()
    #expect(names == ["weather"])
  }

  @Test
  func `addTools appends multiple tools`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.addTools([WeatherTool(), MathTool()])
    let names = await handle.currentToolNames()
    #expect(Set(names) == ["weather", "math"])
  }

  @Test
  func `addTool rejects duplicate tool-name registration`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.addTool(WeatherTool())
    await #expect(throws: HubBridgeError.self) {
      try await handle.addTool(WeatherTool())
    }
  }

  @Test
  func `removeTool removes by name`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.addTools([WeatherTool(), MathTool()])
    await handle.removeTool(named: "weather")
    let names = await handle.currentToolNames()
    #expect(names == ["math"])
  }

  @Test
  func `removeTool is no-op for unknown name`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.addTool(WeatherTool())
    await handle.removeTool(named: "nonexistent")
    let names = await handle.currentToolNames()
    #expect(names == ["weather"])
  }

  @Test
  func `removeTool then addTool works correctly`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.addTool(WeatherTool())
    await handle.removeTool(named: "weather")
    try await handle.addTool(MathTool())
    let names = await handle.currentToolNames()
    #expect(names == ["math"])
  }
}

@Suite("FastMCPServerHandle Resources")
struct ServerHandleResourceTests {

  @Test
  func `starts with empty resources`() async {
    let handle = FastMCPServerHandle()
    let resources = await handle.currentResources
    #expect(resources.isEmpty)
  }

  @Test
  func `configure seeds initial resources`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.seed(resources: [ConfigResource()])
    let resources = await handle.currentResources
    #expect(resources.count == 1)
  }

  @Test
  func `addResource appends a resource`() async {
    let handle = FastMCPServerHandle()
    await handle.addResource(ConfigResource())
    let resources = await handle.currentResources
    #expect(resources.count == 1)
    #expect(resources.first?.uri == "config://app/settings")
  }

  @Test
  func `addResources appends multiple resources`() async {
    let handle = FastMCPServerHandle()
    await handle.addResources([ConfigResource(), SystemInfoResource()])
    let resources = await handle.currentResources
    #expect(resources.count == 2)
  }

  @Test
  func `addResource deduplicates by URI`() async {
    let handle = FastMCPServerHandle()
    await handle.addResource(ConfigResource())
    await handle.addResource(ConfigResource())
    let resources = await handle.currentResources
    #expect(resources.count == 1)
  }

  @Test
  func `removeResource removes by URI`() async {
    let handle = FastMCPServerHandle()
    await handle.addResources([ConfigResource(), SystemInfoResource()])
    await handle.removeResource(uri: "config://app/settings")
    let resources = await handle.currentResources
    #expect(resources.count == 1)
    #expect(resources.first?.uri == "system://info")
  }

  @Test
  func `removeResource is no-op for unknown URI`() async {
    let handle = FastMCPServerHandle()
    await handle.addResource(ConfigResource())
    await handle.removeResource(uri: "nonexistent://uri")
    let resources = await handle.currentResources
    #expect(resources.count == 1)
  }
}

@Suite("FastMCPServerHandle Prompts")
struct ServerHandlePromptTests {

  @Test
  func `starts with empty prompts`() async {
    let handle = FastMCPServerHandle()
    let prompts = await handle.currentPrompts
    #expect(prompts.isEmpty)
  }

  @Test
  func `configure seeds initial prompts`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.seed(prompts: [GreetingPrompt()])
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }

  @Test
  func `addPrompt appends a prompt`() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompt(GreetingPrompt())
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
    #expect(prompts.first?.name == "greeting")
  }

  @Test
  func `addPrompts appends multiple prompts`() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompts([GreetingPrompt()])
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }

  @Test
  func `addPrompt deduplicates by name`() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompt(GreetingPrompt())
    await handle.addPrompt(GreetingPrompt())
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }

  @Test
  func `removePrompt removes by name`() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompt(GreetingPrompt())
    await handle.removePrompt(named: "greeting")
    let prompts = await handle.currentPrompts
    #expect(prompts.isEmpty)
  }

  @Test
  func `removePrompt is no-op for unknown name`() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompt(GreetingPrompt())
    await handle.removePrompt(named: "nonexistent")
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }
}

// MARK: - Integration: Handle + Server Re-registration

@Suite("FastMCPServerHandle Server Integration")
struct ServerHandleIntegrationTests {

  @Test
  func `addTool re-registers handler on connected server`() async throws {
    let server = Server(
      name: "TestServer",
      version: "1.0.0",
      capabilities: .init(tools: .init(listChanged: true))
    )
    await server.register(hubTools: try HubToolAdapter(tools: [WeatherTool()]))

    let handle = FastMCPServerHandle()
    try await handle.seed(tools: [WeatherTool()])
    await handle.registerServer(server)

    try await handle.addTool(MathTool())

    let names = await handle.currentToolNames()
    #expect(Set(names) == ["weather", "math"])
  }

  @Test
  func `removeTool re-registers handler on connected server`() async throws {
    let server = Server(
      name: "TestServer",
      version: "1.0.0",
      capabilities: .init(tools: .init(listChanged: true))
    )
    await server.register(hubTools: try HubToolAdapter(tools: [WeatherTool(), MathTool()]))

    let handle = FastMCPServerHandle()
    try await handle.seed(tools: [WeatherTool(), MathTool()])
    await handle.registerServer(server)

    await handle.removeTool(named: "weather")

    let names = await handle.currentToolNames()
    #expect(names == ["math"])
  }

  @Test
  func `addResource re-registers handler on connected server`() async throws {
    let server = Server(
      name: "TestServer",
      version: "1.0.0",
      capabilities: .init(resources: .init(listChanged: true))
    )
    await server.register(resources: [])

    let handle = FastMCPServerHandle()
    try await handle.seed()
    await handle.registerServer(server)

    await handle.addResource(ConfigResource())

    let resources = await handle.currentResources
    #expect(resources.count == 1)
  }

  @Test
  func `addPrompt re-registers handler on connected server`() async throws {
    let server = Server(
      name: "TestServer",
      version: "1.0.0",
      capabilities: .init(prompts: .init(listChanged: true))
    )
    await server.register(prompts: [])

    let handle = FastMCPServerHandle()
    try await handle.seed()
    await handle.registerServer(server)

    await handle.addPrompt(GreetingPrompt())

    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }

  @Test
  func `handle works with no registered servers`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.addTool(WeatherTool())
    await handle.addResource(ConfigResource())
    await handle.addPrompt(GreetingPrompt())

    let names = await handle.currentToolNames()
    let resources = await handle.currentResources
    let prompts = await handle.currentPrompts

    #expect(names.count == 1)
    #expect(resources.count == 1)
    #expect(prompts.count == 1)
  }

  @Test
  func `configure replaces all existing items`() async throws {
    let handle = FastMCPServerHandle()
    try await handle.addTool(WeatherTool())
    await handle.addResource(ConfigResource())
    await handle.addPrompt(GreetingPrompt())

    try await handle.seed(tools: [MathTool()])

    let names = await handle.currentToolNames()
    let resources = await handle.currentResources
    let prompts = await handle.currentPrompts

    #expect(names == ["math"])
    #expect(resources.isEmpty)
    #expect(prompts.isEmpty)
  }
}
