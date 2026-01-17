import FastMCP

public struct GreetingTool: MCPTool {
  public let name = "greet"
  public let description: String? = "Generate a greeting message"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let name: String
    public let formal: Bool?

    public init(name: String, formal: Bool? = nil) {
      self.name = name
      self.formal = formal
    }
  }

  public func call(with arguments: Parameters) async throws(ToolError) -> Content {
    let greeting =
      arguments.formal == true
      ? "Good day, \(arguments.name)."
      : "Hey \(arguments.name)!"
    return [ToolContentItem(text: greeting)]
  }
}
