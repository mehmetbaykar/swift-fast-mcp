import ExampleTools
import FastMCP
import Logging

@main
struct ExampleServer {
  static func main() async throws {
    var logger = Logger(label: "FastMCP Example Server")
    logger.logLevel = .info

    try await FastMCP.builder()
      .name("FastMCP Example Server")
      .title("FastMCP Example")
      .version("2.1.0")
      .instructions("This server provides weather, math, and greeting tools.")

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

      // Capabilities
      .enableCompletions()
      .enableLogging()

      // Transport — HTTP server on port 8080
      .transport(.http(port: 8080))

      // Custom logger - full control over logging configuration
      .logger(logger)

      // Lifecycle hooks
      .onInitialize { clientInfo, capabilities in
        print("Client connected: \(clientInfo.name) v\(clientInfo.version)")
      }
      .onStart {
        print("Server started on http://127.0.0.1:8080/mcp")
      }
      .onShutdown {
        print("Server shutting down")
      }

      .run()
  }
}
