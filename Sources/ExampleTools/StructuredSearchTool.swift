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
    public init(_ description: String) { self.description = description }
  }

  @Parameter("Search query")
  public var query: String

  public func execute() async throws -> SearchResult {
    guard !query.isEmpty else {
      throw QueryError("Query cannot be empty")
    }
    return SearchResult(
      summary: "Found 2 results for \(query)",
      resultCount: 2
    )
  }
}
