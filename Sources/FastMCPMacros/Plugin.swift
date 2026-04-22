import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct FastMCPMacrosPlugin: CompilerPlugin {
  let providingMacros: [any Macro.Type] = [
    MCPPromptMacro.self,
    PromptArgumentMacro.self,
    MCPResourceMacro.self,
  ]
}
