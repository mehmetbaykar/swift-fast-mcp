#if canImport(FastMCPMacros) && canImport(SwiftSyntaxMacrosTestSupport)
  @testable import FastMCPMacros
  import SwiftSyntaxMacros
  import SwiftSyntaxMacrosTestSupport
  import Testing

  @Suite("MCPResource title collision diagnostic")
  struct MCPResourceTitleCollisionMacroTests {

    @Test func `displayTitle colliding with stored property emits diagnostic`() {
      assertMacroExpansion(
        """
        @MCPResource("test://collide", title: "Display Name")
        struct CollidingResource {
          var displayTitle: String? = "local"

          @ResourceContentBuilder
          var content: Content {
            "x"
          }
        }
        """,
        expandedSource: """
          struct CollidingResource {
            var displayTitle: String? = "local"

            @ResourceContentBuilder
            var content: Content {
              "x"
            }
          }

          extension CollidingResource: MCPResource, Swift.Sendable {
          }
          """,
        diagnostics: [
          DiagnosticSpec(
            message: ResourceMacroError.titleCollidesWithStoredProperty.description,
            line: 1,
            column: 1
          )
        ],
        macros: [
          "MCPResource": MCPResourceMacro.self,
        ]
      )
    }
  }
#endif
