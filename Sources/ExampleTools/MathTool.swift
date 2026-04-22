import FastMCP

@Tool("Perform basic math operations")
public struct MathTool {
  public struct CalculationError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
  }

  @Parameter("Operation", oneOf: ["add", "subtract", "multiply", "divide"])
  public var operation: String

  @Parameter("First operand")
  public var a: Double

  @Parameter("Second operand")
  public var b: Double

  public func execute() async throws -> String {
    let result: Double
    switch operation {
    case "add": result = a + b
    case "subtract": result = a - b
    case "multiply": result = a * b
    case "divide":
      guard b != 0 else { throw CalculationError("Division by zero") }
      result = a / b
    default:
      throw CalculationError("Unknown operation: \(operation)")
    }
    return "Result: \(result)"
  }
}
