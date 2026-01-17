import ExampleTools
import FastMCP
import Logging

@main
struct ExampleServer {
  static func main() async throws {
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

      // Logging level see https://swiftpackageindex.com/apple/swift-log/documentation/logging/logger/level
      .logLevel(.info)

      // Graceful shutdown signals see https://swiftpackageindex.com/swift-server/swift-service-lifecycle/documentation/servicelifecycle/servicegroup/init(services:gracefulshutdownsignals:cancellationsignals:logger:)
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
