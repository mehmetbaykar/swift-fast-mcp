import FastMCP

@Generable
public struct Person {
  @Guide(description: "Person's first name")
  public var firstName: String

  @Guide(description: "Person's last name (optional)")
  public var lastName: String?
}

@Tool("Generate a greeting for a person")
public struct GreetingTool {
  @Generable
  public struct Arguments {
    @Parameter("The person to greet")
    public var person: Person

    @Parameter("Tone to use")
    public var tone: GreetingTone
  }

  public func execute(_ arguments: Arguments) async throws -> String {
    let name = [arguments.person.firstName, arguments.person.lastName].compactMap { $0 }.joined(
      separator: " ")
    switch arguments.tone {
    case .casual: return "Hey \(name)!"
    case .formal: return "Good day, \(name)."
    case .professional: return "Hello \(name), how can I help you today?"
    }
  }
}
