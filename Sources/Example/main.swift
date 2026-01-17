import ExampleTools
import FastMCP

@main
struct ExampleServer {
  static func main() async throws {
    let tools: [any MCPTool] = [
      WeatherTool(),
      MathTool(),
      GreetingTool(),
    ]
    try await FastMCP.builder()
      .name("FastMCP Example Server")
      .version("1.0.0")
      .addTools(tools)
      .logLevel(.info)
      .onStart {
        let numberOfTools = tools.count
        let toolNames = tools.map { $0.name }.joined(separator: ", ")
        print("Example server started with \(numberOfTools) tools: \(toolNames)")
      }
      .onShutdown {
        print("Example server shutting down")
      }
      .run()
  }
}
