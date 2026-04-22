import FastMCP

public struct MathTool: SwiftAIHub.Tool {
  public let name = "calculate"
  public let description = "Perform basic math operations"

  public struct CalculationError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
  }

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Operation: add, subtract, multiply, divide")
    public let operation: String
    @Guide(description: "First operand")
    public let a: Double
    @Guide(description: "Second operand")
    public let b: Double
  }

  public init() {}

  public func call(arguments: Arguments) async throws -> String {
    let result: Double
    switch arguments.operation {
    case "add": result = arguments.a + arguments.b
    case "subtract": result = arguments.a - arguments.b
    case "multiply": result = arguments.a * arguments.b
    case "divide":
      guard arguments.b != 0 else { throw CalculationError("Division by zero") }
      result = arguments.a / arguments.b
    default:
      throw CalculationError("Unknown operation: \(arguments.operation)")
    }
    return "Result: \(result)"
  }
}
