import ExampleTools
import FastMCP
import Logging

@main
struct ExampleServer {
  static func main() async throws {
    let logger: Logger = {
      var log = Logger(label: "FastMCP Example Server")
      log.logLevel = .info
      return log
    }()

    try await FastMCP.builder()
      .name("FastMCP Example Server")
      .title("FastMCP Example")
      .version("2.5.0")
      .instructions("This server provides weather, math, greeting, and structured search tools.")

      // Tools - AI-callable functions
      .addTools([
        WeatherTool(),
        MathTool(),
        GreetingTool(),
        StructuredSearchTool(),
      ])

      // Resources - Static or dynamic data sources
      .addResources([
        ConfigResource(),
        SystemInfoResource(),
      ])

      // Prompts - Reusable conversation templates
      .addPrompts([
        GreetingPrompt(),
        CodeReviewPrompt(),
      ])

      // Capabilities
      .enableCompletions()
      .enableLogging()

      // Transport — stdio (canonical MCP setup for Claude Desktop and CLI clients)
      .transport(.stdio)

      // Custom logger - full control over logging configuration
      .logger(logger)

      // Lifecycle hooks
      //
      // Stdio note: the server owns stdout for the JSON-RPC framing, so `print`
      // would corrupt the wire. We route lifecycle messages through `logger`
      // (which goes to stderr via `StreamLogHandler`) instead.
      .onInitialize { clientInfo, _ in
        logger.info("Client connected: \(clientInfo.name) v\(clientInfo.version)")
      }
      .onStart {
        logger.info("Server started on stdio")
      }
      .onShutdown {
        logger.info("Server shutting down")
      }

      .run()
  }
}
