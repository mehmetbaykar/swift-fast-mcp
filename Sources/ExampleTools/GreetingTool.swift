import FastMCP

public struct GreetingTool: SwiftAIHub.Tool {
  public let name = "greet"
  public let description = "Generate a greeting message"

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Who to greet")
    public let name: String
    @Guide(description: "Use formal tone")
    public let formal: Bool?
  }

  public init() {}

  public func call(arguments: Arguments) async throws -> String {
    arguments.formal == true ? "Good day, \(arguments.name)." : "Hey \(arguments.name)!"
  }
}
