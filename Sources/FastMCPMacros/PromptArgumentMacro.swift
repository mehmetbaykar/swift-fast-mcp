import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro. Collected by `@MCPPrompt` at expansion time; emits no peers.
public struct PromptArgumentMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    []
  }
}
