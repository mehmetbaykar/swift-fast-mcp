import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Expands `@MCPResource(uri, name:, description:, mimeType:)` on a struct:
/// synthesises `uri`, `name`, `description`, `mimeType`, and an empty `init()`.
/// The `content` body remains user-declared.
public struct MCPResourceMacro: MemberMacro, ExtensionMacro {

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let uri = extractURI(from: node) else {
      throw ResourceMacroError.missingURI
    }
    guard declaration.is(StructDeclSyntax.self) else {
      throw ResourceMacroError.onlyApplicableToStruct
    }

    var members: [DeclSyntax] = [
      "public var uri: String { \(raw: literalString(uri)) }"
    ]

    if let name = extractLabeledString(from: node, label: "name") {
      members.append("public var name: String? { \(raw: literalString(name)) }")
    }
    if let description = extractLabeledString(from: node, label: "description") {
      members.append(
        "public var description: String? { \(raw: literalString(description)) }"
      )
    }
    if let mimeType = extractMimeType(from: node) {
      members.append("public var mimeType: String? { \(raw: literalString(mimeType)) }")
    }

    if !hasInit(in: declaration) {
      members.append("public init() {}")
    }

    return members
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(StructDeclSyntax.self),
      extractURI(from: node) != nil
    else {
      return []
    }
    let ext = try ExtensionDeclSyntax(
      "extension \(type): MCPResource, Swift.Sendable {}"
    )
    return [ext]
  }

  // MARK: - Attribute parsing

  private static func extractURI(from node: AttributeSyntax) -> String? {
    guard let list = node.arguments?.as(LabeledExprListSyntax.self),
      let first = list.first,
      first.label == nil,
      let literal = first.expression.as(StringLiteralExprSyntax.self),
      let segment = literal.segments.first?.as(StringSegmentSyntax.self)
    else {
      return nil
    }
    return segment.content.text
  }

  private static func extractLabeledString(
    from node: AttributeSyntax,
    label: String
  ) -> String? {
    guard let list = node.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in list where arg.label?.text == label {
      if let literal = arg.expression.as(StringLiteralExprSyntax.self),
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
      {
        return segment.content.text
      }
    }
    return nil
  }

  /// Resolves the `mimeType:` argument. Accepts either `.caseName` shorthand
  /// or `.other("…")` enum literals from `MCPResourceMimeType`.
  private static func extractMimeType(from node: AttributeSyntax) -> String? {
    guard let list = node.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in list where arg.label?.text == "mimeType" {
      if let member = arg.expression.as(MemberAccessExprSyntax.self),
        member.base == nil
      {
        return mapMimeCase(member.declName.baseName.text)
      }
      if let call = arg.expression.as(FunctionCallExprSyntax.self),
        let member = call.calledExpression.as(MemberAccessExprSyntax.self),
        member.base == nil,
        member.declName.baseName.text == "other",
        let firstArg = call.arguments.first,
        let literal = firstArg.expression.as(StringLiteralExprSyntax.self),
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
      {
        return segment.content.text
      }
    }
    return nil
  }

  private static func mapMimeCase(_ name: String) -> String? {
    switch name {
    case "applicationJSON": return "application/json"
    case "applicationXML": return "application/xml"
    case "applicationOctetStream": return "application/octet-stream"
    case "textPlain": return "text/plain"
    case "textMarkdown": return "text/markdown"
    case "textHTML": return "text/html"
    case "textCSV": return "text/csv"
    case "imagePNG": return "image/png"
    case "imageJPEG": return "image/jpeg"
    default: return nil
    }
  }

  private static func hasInit(in declaration: some DeclGroupSyntax) -> Bool {
    for member in declaration.memberBlock.members
    where member.decl.is(InitializerDeclSyntax.self) {
      return true
    }
    return false
  }

  // MARK: - Helpers

  private static func literalString(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
  }
}

enum ResourceMacroError: Error, CustomStringConvertible {
  case missingURI
  case onlyApplicableToStruct

  var description: String {
    switch self {
    case .missingURI: return "@MCPResource requires a URI string"
    case .onlyApplicableToStruct: return "@MCPResource can only be applied to structs"
    }
  }
}
