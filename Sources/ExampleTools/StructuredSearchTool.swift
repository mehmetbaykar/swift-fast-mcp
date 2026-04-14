import FastMCP

public struct StructuredSearchTool: MCPStructuredTool {
  public typealias Output = SearchResult

  public let name = "structured_search"
  public let description: String? = "Return search results with typed structured output"

  public init() {}

  @Schemable
  public struct Parameters: Sendable {
    public let query: String

    public init(query: String) {
      self.query = query
    }
  }

  @Schemable
  public struct SearchResult: Codable, Sendable {
    public let summary: String
    public let resultCount: Int

    public init(summary: String, resultCount: Int) {
      self.summary = summary
      self.resultCount = resultCount
    }
  }

  public func callStructured(with arguments: Parameters) async throws(ToolError)
    -> StructuredToolResult<SearchResult>
  {
    guard !arguments.query.isEmpty else {
      throw ToolError("Query cannot be empty")
    }

    let summary = "Found 2 results for \(arguments.query)"
    return StructuredToolResult(
      structuredContent: SearchResult(summary: summary, resultCount: 2)
    ) {
      ToolContentItem(text: summary)
    }
  }
}
