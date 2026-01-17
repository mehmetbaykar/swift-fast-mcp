import ExampleTools
import FastMCP
import Logging

@main
struct ExampleServer {
  static func main() async throws {
    // Custom logger - configure level, handlers, metadata as needed
    var logger = Logger(label: "FastMCP Example Server")
    logger.logLevel = .info

    try await FastMCP.builder()
      .name("FastMCP Example Server")
      .version("1.0.0")

      // Tools - AI-callable functions
      .addTools([
        WeatherTool(),
        MathTool(),
        GreetingTool(),
      ])

      // Resources - Static or dynamic data sources
      .addResources([
        ConfigResource(),
        SystemInfoResource(),
      ])

      // Prompts - Reusable conversation templates
      .addPrompts([
        GreetingPrompt()
      ])

      // Sampling - Enable LLM sampling capability
      .enableSampling()

      // Transport - stdio (default), inMemory, or custom
      .transport(.stdio)

      // Custom logger - full control over logging configuration
      .logger(logger)

      // Graceful shutdown signals
      .shutdownSignals([.sigterm, .sigint])

      // Lifecycle hooks
      .onStart {
        print("Server started successfully")
      }
      .onShutdown {
        print("Server shutting down")
      }

      .run()
  }
}
