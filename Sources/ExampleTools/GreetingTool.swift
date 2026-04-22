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
  @Parameter("The person to greet")
  public var person: Person = Person(firstName: "", lastName: nil)

  @Parameter("Tone to use")
  public var tone: GreetingTone = .casual

  public func execute() async throws -> String {
    let name = [person.firstName, person.lastName].compactMap { $0 }.joined(separator: " ")
    switch tone {
    case .casual: return "Hey \(name)!"
    case .formal: return "Good day, \(name)."
    case .professional: return "Hello \(name), how can I help you today?"
    }
  }
}
