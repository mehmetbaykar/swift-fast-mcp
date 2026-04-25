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

  @Parameter("Operation")
  public var operation: MathOperation = .add

  @Parameter("First operand")
  public var a: Double = 0

  @Parameter("Second operand")
  public var b: Double = 0

  public init() {}

  public func execute() async throws -> String {
    let result: Double
    switch operation {
    case .add: result = a + b
    case .subtract: result = a - b
    case .multiply: result = a * b
    case .divide:
      guard b != 0 else { throw CalculationError(description: "Division by zero") }
      result = a / b
    }
    return "Result: \(result)"
  }
}
