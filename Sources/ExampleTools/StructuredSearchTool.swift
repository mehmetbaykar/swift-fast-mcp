import FastMCP

@Generable
public struct SearchResult {
  @Guide(description: "Human readable summary")
  public var summary: String
  @Guide(description: "Number of results")
  public var resultCount: Int
}

@Tool("Return search results with typed structured output")
public struct StructuredSearchTool {
  public struct QueryError: Error, CustomStringConvertible {
    public let description: String
  }

  @Generable
  public struct Arguments {
    @Parameter("Search query")
    public var query: String
  }

  public func execute(_ arguments: Arguments) async throws -> SearchResult {
    guard !arguments.query.isEmpty else {
      throw QueryError(description: "Query cannot be empty")
    }
    return SearchResult(
      summary: "Found 2 results for \(arguments.query)",
      resultCount: 2
    )
  }
}
