import ExampleTools
import Foundation
import Logging
import Testing
import UnixSignals

@testable import FastMCP

@Suite("FastMCP Builder Tests")
struct BuilderTests {

  @Test
  func builderUsesProcessNameAsDefaultServerName() {
    let builder = FastMCP.builder()
    #expect(builder.serverName == ProcessInfo.processInfo.processName)
  }

  @Test
  func builderUsesDefaultVersion() {
    let builder = FastMCP.builder()
    #expect(builder.serverVersion == "1.0.0")
  }

  @Test
  func builderUsesStdioTransportByDefault() {
    let builder = FastMCP.builder()
    if case .stdio = builder.transportConfig {
      #expect(true)
    } else {
      Issue.record("Expected stdio transport by default")
    }
  }

  @Test
  func builderUsesInfoLogLevelByDefault() {
    let builder = FastMCP.builder()
    #expect(builder.logLevel == .info)
  }

  @Test
  func builderUsesDefaultShutdownSignals() {
    let builder = FastMCP.builder()
    #expect(builder.shutdownSignals.contains(.sigterm))
    #expect(builder.shutdownSignals.contains(.sigint))
  }

  @Test
  func builderStartsWithEmptyTools() {
    let builder = FastMCP.builder()
    #expect(builder.tools.isEmpty)
  }

  @Test
  func builderStartsWithEmptyResources() {
    let builder = FastMCP.builder()
    #expect(builder.resources.isEmpty)
  }

  @Test
  func builderStartsWithEmptyPrompts() {
    let builder = FastMCP.builder()
    #expect(builder.prompts.isEmpty)
  }

  @Test
  func samplingIsDisabledByDefault() {
    let builder = FastMCP.builder()
    #expect(builder.samplingEnabled == false)
  }

  @Test
  func nameMethodUpdatesServerName() {
    let builder = FastMCP.builder().name("CustomServer")
    #expect(builder.serverName == "CustomServer")
  }

  @Test
  func versionMethodUpdatesServerVersion() {
    let builder = FastMCP.builder().version("2.5.0")
    #expect(builder.serverVersion == "2.5.0")
  }

  @Test
  func addToolsMethodAddsTools() {
    let builder = FastMCP.builder().addTools([WeatherTool(), MathTool()])
    #expect(builder.tools.count == 2)
    let toolNames = builder.tools.map { $0.name }
    #expect(toolNames.contains("get_weather"))
    #expect(toolNames.contains("calculate"))
  }

  @Test
  func addToolsMethodDeduplicatesToolsWithSameName() {
    let builder = FastMCP.builder()
      .addTools([WeatherTool()])
      .addTools([WeatherTool(), MathTool()])
    #expect(builder.tools.count == 2)
  }

  @Test
  func addPromptsMethodAddsPrompts() {
    let builder = FastMCP.builder().addPrompts([GreetingPrompt()])
    #expect(builder.prompts.count == 1)
    #expect(builder.prompts.first?.name == "greeting")
  }

  @Test
  func addPromptsMethodDeduplicatesPromptsWithSameName() {
    let builder = FastMCP.builder()
      .addPrompts([GreetingPrompt()])
      .addPrompts([GreetingPrompt()])
    #expect(builder.prompts.count == 1)
  }

  @Test
  func enableSamplingMethodEnablesSampling() {
    let builder = FastMCP.builder().enableSampling()
    #expect(builder.samplingEnabled == true)
  }

  @Test
  func enableSamplingWithFalseDisablesSampling() {
    let builder = FastMCP.builder().enableSampling(true).enableSampling(false)
    #expect(builder.samplingEnabled == false)
  }

  @Test
  func transportMethodUpdatesTransportConfig() {
    let builder = FastMCP.builder().transport(.inMemory)
    if case .inMemory = builder.transportConfig {
      #expect(true)
    } else {
      Issue.record("Expected inMemory transport")
    }
  }

  @Test
  func logLevelMethodUpdatesLogLevel() {
    let builder = FastMCP.builder().logLevel(.debug)
    #expect(builder.logLevel == .debug)
  }

  @Test
  func shutdownSignalsMethodUpdatesSignals() {
    let builder = FastMCP.builder().shutdownSignals([.sigterm])
    #expect(builder.shutdownSignals.count == 1)
    #expect(builder.shutdownSignals.contains(.sigterm))
  }

  @Test
  func onStartMethodSetsHandler() {
    let builder = FastMCP.builder().onStart {}
    #expect(builder.onStartHandler != nil)
  }

  @Test
  func onShutdownMethodSetsHandler() {
    let builder = FastMCP.builder().onShutdown {}
    #expect(builder.onShutdownHandler != nil)
  }

  @Test
  func builderChainWorksWithAllOptions() {
    let builder = FastMCP.builder()
      .name("FullServer")
      .version("3.0.0")
      .addTools([WeatherTool()])
      .addTools([MathTool()])
      .addPrompts([GreetingPrompt()])
      .enableSampling()
      .transport(.stdio)
      .logLevel(.warning)
      .shutdownSignals([.sigterm])
      .onStart {}
      .onShutdown {}

    #expect(builder.serverName == "FullServer")
    #expect(builder.serverVersion == "3.0.0")
    #expect(builder.tools.count == 2)
    #expect(builder.prompts.count == 1)
    #expect(builder.samplingEnabled == true)
    #expect(builder.logLevel == .warning)
    #expect(builder.shutdownSignals == [.sigterm])
    #expect(builder.onStartHandler != nil)
    #expect(builder.onShutdownHandler != nil)
  }

  @Test
  func builderCreatesNewInstanceOnEachMethod() {
    let original = FastMCP.builder().name("Original")
    let modified = original.name("Modified")

    #expect(original.serverName == "Original")
    #expect(modified.serverName == "Modified")
  }

  @Test
  func inMemoryTransportIsAvailable() {
    let builder = FastMCP.builder().transport(.inMemory)
    if case .inMemory = builder.transportConfig {
      #expect(true)
    } else {
      Issue.record("Expected inMemory transport")
    }
  }
}
