import Foundation
import MCP

extension Resource.Content {
  /// Creates a `Resource.Content` with a base64-encoded blob.
  public static func blob(_ base64Data: String, uri: String, mimeType: String? = nil) -> Self {
    guard let data = Data(base64Encoded: base64Data) else {
      return .binary(Data(), uri: uri, mimeType: mimeType)
    }
    return .binary(data, uri: uri, mimeType: mimeType)
  }
}

extension MCPResource {
  public func toResource() -> Resource {
    Resource(
      name: name ?? uri,
      uri: uri,
      description: description,
      mimeType: mimeType
    )
  }

  public func read(uri: String) async throws -> ReadResource.Result {
    let contents = try await self.content
    let resourceContents = contents.map { item in
      switch item.content {
      case .text(let text):
        return Resource.Content.text(text, uri: uri, mimeType: item.mimeType)
      case .blob(let base64Data):
        return Resource.Content.blob(base64Data, uri: uri, mimeType: item.mimeType)
      }
    }
    return ReadResource.Result(contents: resourceContents)
  }
}

extension Server {
  public func register(resources: [any MCPResource]) async {
    self.withMethodHandler(ListResources.self) { _ in
      .init(resources: resources.map { $0.toResource() })
    }

    self.withMethodHandler(ReadResource.self) { params async throws in
      guard let resource = resources.first(where: { $0.uri == params.uri }) else {
        throw MCPError.invalidRequest("Unknown resource URI: \(params.uri)")
      }
      return try await resource.read(uri: params.uri)
    }
  }
}
