import FastMCP

@Tool("Generate a greeting message")
public struct GreetingTool {
  @Parameter("Who to greet")
  public var who: String

  @Parameter("Use formal tone")
  public var formal: Bool? = nil

  public func execute() async throws -> String {
    formal == true ? "Good day, \(who)." : "Hey \(who)!"
  }
}
