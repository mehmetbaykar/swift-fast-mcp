#if canImport(FastMCPMacros) && canImport(SwiftSyntaxMacrosTestSupport)
  import FastMCPMacros
  import SwiftSyntaxMacros
  import SwiftSyntaxMacrosTestSupport
  import Testing

  @Suite("MCPPrompt title collision diagnostic")
  struct MCPPromptTitleCollisionMacroTests {

    @Test func `title argument colliding with stored property emits diagnostic`() {
      assertMacroExpansion(
        """
        @MCPPrompt("Colliding prompt", title: "Display Name")
        struct CollidingPrompt {
          @PromptArgument("Document title")
          var title: String

          func getMessages() async throws -> Messages {
            [.user(title)]
          }
        }
        """,
        expandedSource: """
          struct CollidingPrompt {
            var title: String

            func getMessages() async throws -> Messages {
              [.user(title)]
            }
          }

          extension CollidingPrompt: MCPPrompt, Swift.Sendable {
          }
          """,
        diagnostics: [
          DiagnosticSpec(
            message:
              "Cannot use title: on @MCPPrompt when the struct already has a stored property named \"title\". Rename the property and keep the wire name with @PromptArgument(..., name: \"title\").",
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
