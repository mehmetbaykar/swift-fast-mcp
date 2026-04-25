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

  @Parameter("Search query")
  public var query: String = ""

  public init() {}

  public func execute() async throws -> SearchResult {
    guard !query.isEmpty else {
      throw QueryError(description: "Query cannot be empty")
    }
    return SearchResult(
      summary: "Found 2 results for \(query)",
      resultCount: 2
    )
  }
}
