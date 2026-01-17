import FastMCP

public struct MathTool: MCPTool {
  public let name = "calculate"
  public let description: String? = "Perform basic math operations"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let operation: Operation
    public let a: Double
    public let b: Double

    public init(operation: Operation, a: Double, b: Double) {
      self.operation = operation
      self.a = a
      self.b = b
    }
  }

  @Schemable
  public enum Operation: String, Sendable {
    case add
    case subtract
    case multiply
    case divide
  }

  public func call(with arguments: Parameters) async throws(ToolError) -> Content {
    let result: Double =
      switch arguments.operation {
      case .add: arguments.a + arguments.b
      case .subtract: arguments.a - arguments.b
      case .multiply: arguments.a * arguments.b
      case .divide:
        if arguments.b == 0 {
          throw ToolError("Division by zero")
        } else {
          arguments.a / arguments.b
        }
      }
    return [ToolContentItem(text: "Result: \(result)")]
  }
}
