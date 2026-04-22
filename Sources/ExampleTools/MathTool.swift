import FastMCP

@Generable
public enum MathOperation: String, CaseIterable {
  case add, subtract, multiply, divide
}

@Tool("Perform basic math operations")
public struct MathTool {
  public struct CalculationError: Error, CustomStringConvertible {
    public let description: String
  }

  @Generable
  public struct Arguments {
    @Parameter("Operation")
    public var operation: MathOperation

    @Parameter("First operand")
    public var a: Double

    @Parameter("Second operand")
    public var b: Double
  }

  public func execute(_ arguments: Arguments) async throws -> String {
    let result: Double
    switch arguments.operation {
    case .add: result = arguments.a + arguments.b
    case .subtract: result = arguments.a - arguments.b
    case .multiply: result = arguments.a * arguments.b
    case .divide:
      guard arguments.b != 0 else { throw CalculationError(description: "Division by zero") }
      result = arguments.a / arguments.b
    }
    return "Result: \(result)"
  }
}
