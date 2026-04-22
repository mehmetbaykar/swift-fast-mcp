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
  ) async {
    await configure(
      toolAdapter: HubToolAdapter(tools: tools),
      resources: resources,
      prompts: prompts
    )
  }
}

// MARK: - CapabilitiesBuilder listChanged Tests

@Suite("CapabilitiesBuilder listChanged")
struct CapabilitiesBuilderListChangedTests {

  @Test("listChanged defaults to false")
  func listChangedDefaultsToFalse() {
    let capabilities = CapabilitiesBuilder.build(
      hasTools: true,
      hasResources: true,
      hasPrompts: true
    )

    #expect(capabilities.tools?.listChanged == false)
    #expect(capabilities.resources?.listChanged == false)
    #expect(capabilities.prompts?.listChanged == false)
  }

  @Test("listChanged true is propagated to all capabilities")
  func listChangedTrueIsPropagated() {
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

  @Test("listChanged true only applies to enabled capabilities")
  func listChangedOnlyAppliesWhenEnabled() {
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

  @Test("serverHandle defaults to nil")
  func handleDefaultsToNil() {
    let builder = FastMCP.builder()
    #expect(builder.handle == nil)
  }

  @Test("serverHandle stores the handle")
  func handleIsStored() {
    let handle = FastMCPServerHandle()
    let builder = FastMCP.builder().serverHandle(handle)
    #expect(builder.handle != nil)
  }

  @Test("serverHandle preserves value semantics")
  func handlePreservesValueSemantics() {
    let handle = FastMCPServerHandle()
    let original = FastMCP.builder()
    let modified = original.serverHandle(handle)

    #expect(original.handle == nil)
    #expect(modified.handle != nil)
  }

  @Test("Builder chain works with serverHandle")
  func builderChainWithHandle() {
    let handle = FastMCPServerHandle()
    let builder = FastMCP.builder()
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

  @Test("starts with empty tools")
  func startsEmpty() async {
    let handle = FastMCPServerHandle()
    let names = await handle.currentToolNames()
    #expect(names.isEmpty)
  }

  @Test("configure seeds initial tools")
  func configureSeedsTools() async {
    let handle = FastMCPServerHandle()
    await handle.seed(tools: [WeatherTool()])
    let names = await handle.currentToolNames()
    #expect(names == ["get_weather"])
  }

  @Test("addTool appends a tool")
  func addToolAppends() async {
    let handle = FastMCPServerHandle()
    await handle.addTool(WeatherTool())
    let names = await handle.currentToolNames()
    #expect(names == ["get_weather"])
  }

  @Test("addTools appends multiple tools")
  func addToolsAppendsMultiple() async {
    let handle = FastMCPServerHandle()
    await handle.addTools([WeatherTool(), MathTool()])
    let names = await handle.currentToolNames()
    #expect(Set(names) == ["get_weather", "calculate"])
  }

  @Test("addTool deduplicates by name")
  func addToolDeduplicates() async {
    let handle = FastMCPServerHandle()
    await handle.addTool(WeatherTool())
    await handle.addTool(WeatherTool())
    let names = await handle.currentToolNames()
    #expect(names.count == 1)
  }

  @Test("removeTool removes by name")
  func removeToolByName() async {
    let handle = FastMCPServerHandle()
    await handle.addTools([WeatherTool(), MathTool()])
    await handle.removeTool(named: "get_weather")
    let names = await handle.currentToolNames()
    #expect(names == ["calculate"])
  }

  @Test("removeTool is no-op for unknown name")
  func removeToolUnknownName() async {
    let handle = FastMCPServerHandle()
    await handle.addTool(WeatherTool())
    await handle.removeTool(named: "nonexistent")
    let names = await handle.currentToolNames()
    #expect(names == ["get_weather"])
  }

  @Test("removeTool then addTool works correctly")
  func removeAndReAdd() async {
    let handle = FastMCPServerHandle()
    await handle.addTool(WeatherTool())
    await handle.removeTool(named: "get_weather")
    await handle.addTool(MathTool())
    let names = await handle.currentToolNames()
    #expect(names == ["calculate"])
  }
}

@Suite("FastMCPServerHandle Resources")
struct ServerHandleResourceTests {

  @Test("starts with empty resources")
  func startsEmpty() async {
    let handle = FastMCPServerHandle()
    let resources = await handle.currentResources
    #expect(resources.isEmpty)
  }

  @Test("configure seeds initial resources")
  func configureSeedsResources() async {
    let handle = FastMCPServerHandle()
    await handle.seed(resources: [ConfigResource()])
    let resources = await handle.currentResources
    #expect(resources.count == 1)
  }

  @Test("addResource appends a resource")
  func addResourceAppends() async {
    let handle = FastMCPServerHandle()
    await handle.addResource(ConfigResource())
    let resources = await handle.currentResources
    #expect(resources.count == 1)
    #expect(resources.first?.uri == "config://app/settings")
  }

  @Test("addResources appends multiple resources")
  func addResourcesAppendsMultiple() async {
    let handle = FastMCPServerHandle()
    await handle.addResources([ConfigResource(), SystemInfoResource()])
    let resources = await handle.currentResources
    #expect(resources.count == 2)
  }

  @Test("addResource deduplicates by URI")
  func addResourceDeduplicates() async {
    let handle = FastMCPServerHandle()
    await handle.addResource(ConfigResource())
    await handle.addResource(ConfigResource())
    let resources = await handle.currentResources
    #expect(resources.count == 1)
  }

  @Test("removeResource removes by URI")
  func removeResourceByURI() async {
    let handle = FastMCPServerHandle()
    await handle.addResources([ConfigResource(), SystemInfoResource()])
    await handle.removeResource(uri: "config://app/settings")
    let resources = await handle.currentResources
    #expect(resources.count == 1)
    #expect(resources.first?.uri == "system://info")
  }

  @Test("removeResource is no-op for unknown URI")
  func removeResourceUnknownURI() async {
    let handle = FastMCPServerHandle()
    await handle.addResource(ConfigResource())
    await handle.removeResource(uri: "nonexistent://uri")
    let resources = await handle.currentResources
    #expect(resources.count == 1)
  }
}

@Suite("FastMCPServerHandle Prompts")
struct ServerHandlePromptTests {

  @Test("starts with empty prompts")
  func startsEmpty() async {
    let handle = FastMCPServerHandle()
    let prompts = await handle.currentPrompts
    #expect(prompts.isEmpty)
  }

  @Test("configure seeds initial prompts")
  func configureSeedsPrompts() async {
    let handle = FastMCPServerHandle()
    await handle.seed(prompts: [GreetingPrompt()])
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }

  @Test("addPrompt appends a prompt")
  func addPromptAppends() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompt(GreetingPrompt())
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
    #expect(prompts.first?.name == "greeting")
  }

  @Test("addPrompts appends multiple prompts")
  func addPromptsAppendsMultiple() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompts([GreetingPrompt()])
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }

  @Test("addPrompt deduplicates by name")
  func addPromptDeduplicates() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompt(GreetingPrompt())
    await handle.addPrompt(GreetingPrompt())
    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }

  @Test("removePrompt removes by name")
  func removePromptByName() async {
    let handle = FastMCPServerHandle()
    await handle.addPrompt(GreetingPrompt())
    await handle.removePrompt(named: "greeting")
    let prompts = await handle.currentPrompts
    #expect(prompts.isEmpty)
  }

  @Test("removePrompt is no-op for unknown name")
  func removePromptUnknownName() async {
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

  @Test("addTool re-registers handler on connected server")
  func addToolReregistersHandler() async throws {
    let server = Server(
      name: "TestServer",
      version: "1.0.0",
      capabilities: .init(tools: .init(listChanged: true))
    )
    await server.register(hubTools: HubToolAdapter(tools: [WeatherTool()]))

    let handle = FastMCPServerHandle()
    await handle.seed(tools: [WeatherTool()])
    await handle.registerServer(server)

    await handle.addTool(MathTool())

    let names = await handle.currentToolNames()
    #expect(Set(names) == ["get_weather", "calculate"])
  }

  @Test("removeTool re-registers handler on connected server")
  func removeToolReregistersHandler() async throws {
    let server = Server(
      name: "TestServer",
      version: "1.0.0",
      capabilities: .init(tools: .init(listChanged: true))
    )
    await server.register(hubTools: HubToolAdapter(tools: [WeatherTool(), MathTool()]))

    let handle = FastMCPServerHandle()
    await handle.seed(tools: [WeatherTool(), MathTool()])
    await handle.registerServer(server)

    await handle.removeTool(named: "get_weather")

    let names = await handle.currentToolNames()
    #expect(names == ["calculate"])
  }

  @Test("addResource re-registers handler on connected server")
  func addResourceReregistersHandler() async throws {
    let server = Server(
      name: "TestServer",
      version: "1.0.0",
      capabilities: .init(resources: .init(listChanged: true))
    )
    await server.register(resources: [])

    let handle = FastMCPServerHandle()
    await handle.seed()
    await handle.registerServer(server)

    await handle.addResource(ConfigResource())

    let resources = await handle.currentResources
    #expect(resources.count == 1)
  }

  @Test("addPrompt re-registers handler on connected server")
  func addPromptReregistersHandler() async throws {
    let server = Server(
      name: "TestServer",
      version: "1.0.0",
      capabilities: .init(prompts: .init(listChanged: true))
    )
    await server.register(prompts: [])

    let handle = FastMCPServerHandle()
    await handle.seed()
    await handle.registerServer(server)

    await handle.addPrompt(GreetingPrompt())

    let prompts = await handle.currentPrompts
    #expect(prompts.count == 1)
  }

  @Test("handle works with no registered servers")
  func handleWorksWithoutServers() async {
    let handle = FastMCPServerHandle()
    await handle.addTool(WeatherTool())
    await handle.addResource(ConfigResource())
    await handle.addPrompt(GreetingPrompt())

    let names = await handle.currentToolNames()
    let resources = await handle.currentResources
    let prompts = await handle.currentPrompts

    #expect(names.count == 1)
    #expect(resources.count == 1)
    #expect(prompts.count == 1)
  }

  @Test("configure replaces all existing items")
  func configureReplacesAll() async {
    let handle = FastMCPServerHandle()
    await handle.addTool(WeatherTool())
    await handle.addResource(ConfigResource())
    await handle.addPrompt(GreetingPrompt())

    await handle.seed(tools: [MathTool()])

    let names = await handle.currentToolNames()
    let resources = await handle.currentResources
    let prompts = await handle.currentPrompts

    #expect(names == ["calculate"])
    #expect(resources.isEmpty)
    #expect(prompts.isEmpty)
  }
}
