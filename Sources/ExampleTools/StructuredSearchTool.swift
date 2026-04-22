import FastMCP

public struct StructuredSearchTool: SwiftAIHub.Tool {
  public let name = "structured_search"
  public let description = "Return search results with typed structured output"

  public struct QueryError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
  }

  @Generable
  public struct Arguments: Sendable {
    @Guide(description: "Search query")
    public let query: String
  }

  @Generable
  public struct SearchResult: Sendable {
    @Guide(description: "Human readable summary")
    public let summary: String
    @Guide(description: "Number of results")
    public let resultCount: Int
  }

  public init() {}

  public func call(arguments: Arguments) async throws -> SearchResult {
    guard !arguments.query.isEmpty else {
      throw QueryError("Query cannot be empty")
    }
    return SearchResult(
      summary: "Found 2 results for \(arguments.query)",
      resultCount: 2
    )
  }
}
