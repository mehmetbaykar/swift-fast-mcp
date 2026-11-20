#if canImport(FastMCPMacros) && canImport(SwiftSyntaxMacrosTestSupport)
  @testable import FastMCPMacros
  import SwiftSyntaxMacros
  import SwiftSyntaxMacrosTestSupport
  import Testing

  @Suite("MCPPrompt title collision diagnostic")
  struct MCPPromptTitleCollisionMacroTests {

    @Test func `displayTitle colliding with stored property emits diagnostic`() {
      assertMacroExpansion(
        """
        @MCPPrompt("Colliding prompt", title: "Display Name")
        struct CollidingPrompt {
          var displayTitle: String? = "local"

          func getMessages() async throws -> Messages {
            [.user("x")]
          }
        }
        """,
        expandedSource: """
          struct CollidingPrompt {
            var displayTitle: String? = "local"

            func getMessages() async throws -> Messages {
              [.user("x")]
            }
          }

          extension CollidingPrompt: MCPPrompt, Swift.Sendable {
          }
          """,
        diagnostics: [
          DiagnosticSpec(
            message: PromptMacroError.titleCollidesWithStoredProperty.description,
            line: 1,
            column: 1
          )
        ],
        macros: [
          "MCPPrompt": MCPPromptMacro.self,
          "PromptArgument": PromptArgumentMacro.self,
        ]
      )
    }
  }
#endif
