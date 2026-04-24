import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Expands `@MCPPrompt("description", name: "optional")` on a struct:
/// synthesises `name`, `description`, `arguments`, a memberwise `init()`, and a
/// `getMessages(arguments:)` dispatcher that assigns the raw `[String: String]`
/// payload onto `@PromptArgument` properties before invoking the user's
/// zero-arg `getMessages()`.
public struct MCPPromptMacro: MemberMacro, ExtensionMacro {

  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let description = extractDescription(from: node) else {
      throw PromptMacroError.missingDescription
    }
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      throw PromptMacroError.onlyApplicableToStruct
    }

    let typeName = structDecl.name.text
    let promptName = extractName(from: node) ?? derivePromptName(from: typeName)
    let arguments = extractArguments(from: declaration)

    var members: [DeclSyntax] = []
    members.append("public var name: String { \(raw: literalString(promptName)) }")
    members.append(
      "public var description: String? { \(raw: literalString(description)) }"
    )
    members.append(generateArgumentsProperty(arguments))

    if !hasInit(in: declaration) {
      members.append(generateDefaultInit(arguments))
    }

    members.append(generateGetMessages(arguments, promptName: promptName))

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
      extractDescription(from: node) != nil
    else {
      return []
    }
    let ext = try ExtensionDeclSyntax(
      "extension \(type): MCPPrompt, Swift.Sendable {}"
    )
    return [ext]
  }

  // MARK: - Attribute parsing

  private static func extractDescription(from node: AttributeSyntax) -> String? {
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

  private static func extractName(from node: AttributeSyntax) -> String? {
    guard let list = node.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in list where arg.label?.text == "name" {
      if let literal = arg.expression.as(StringLiteralExprSyntax.self),
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
      {
        return segment.content.text
      }
    }
    return nil
  }

  private static func derivePromptName(from typeName: String) -> String {
    var name = typeName
    if name.hasSuffix("Prompt") {
      name = String(name.dropLast("Prompt".count))
    }
    guard let first = name.first else { return name }
    return first.lowercased() + name.dropFirst()
  }

  // MARK: - Argument extraction

  private static func extractArguments(
    from declaration: some DeclGroupSyntax
  ) -> [PromptArgumentInfo] {
    var result: [PromptArgumentInfo] = []
    for member in declaration.memberBlock.members {
      guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
      let attr = varDecl.attributes.first { element in
        guard let attr = element.as(AttributeSyntax.self),
          let ident = attr.attributeName.as(IdentifierTypeSyntax.self)
        else { return false }
        return ident.name.text == "PromptArgument"
      }
      guard let attrSyntax = attr?.as(AttributeSyntax.self) else { continue }
      for binding in varDecl.bindings {
        guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
        let propName = pattern.identifier.text
        let typeAnnotation = binding.typeAnnotation?.type
        let swiftType = typeAnnotation?.description.trimmingCharacters(in: .whitespaces) ?? "String"
        let isOptional =
          typeAnnotation?.is(OptionalTypeSyntax.self) == true
          || typeAnnotation?.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) == true
        let hasDefault = binding.initializer != nil
        let descText = extractArgDescription(from: attrSyntax) ?? ""
        let explicitName = extractArgName(from: attrSyntax)
        let explicitRequired = extractArgRequired(from: attrSyntax)
        let isRequired = explicitRequired ?? !(isOptional || hasDefault)
        result.append(
          PromptArgumentInfo(
            propertyName: propName,
            argumentName: explicitName ?? propName,
            description: descText,
            swiftType: swiftType,
            isOptional: isOptional,
            isRequired: isRequired,
            hasDefault: hasDefault
          ))
      }
    }
    return result
  }

  private static func extractArgDescription(from attr: AttributeSyntax) -> String? {
    guard let list = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in list where arg.label == nil {
      if let literal = arg.expression.as(StringLiteralExprSyntax.self),
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
      {
        return segment.content.text
      }
    }
    return nil
  }

  private static func extractArgName(from attr: AttributeSyntax) -> String? {
    guard let list = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in list where arg.label?.text == "name" {
      if let literal = arg.expression.as(StringLiteralExprSyntax.self),
        let segment = literal.segments.first?.as(StringSegmentSyntax.self)
      {
        return segment.content.text
      }
    }
    return nil
  }

  private static func extractArgRequired(from attr: AttributeSyntax) -> Bool? {
    guard let list = attr.arguments?.as(LabeledExprListSyntax.self) else { return nil }
    for arg in list where arg.label?.text == "required" {
      let text = arg.expression.description.trimmingCharacters(in: .whitespaces)
      if text == "true" { return true }
      if text == "false" { return false }
    }
    return nil
  }

  private static func hasInit(in declaration: some DeclGroupSyntax) -> Bool {
    for member in declaration.memberBlock.members
    where member.decl.is(InitializerDeclSyntax.self) {
      return true
    }
    return false
  }

  // MARK: - Codegen

  private static func generateArgumentsProperty(
    _ arguments: [PromptArgumentInfo]
  ) -> DeclSyntax {
    let entries = arguments.map { arg in
      """
      PromptArgumentSpec(
                  name: \(literalString(arg.argumentName)),
                  description: \(literalString(arg.description)),
                  required: \(arg.isRequired)
              )
      """
    }
    let body =
      entries.isEmpty
      ? "[]"
      : "[\n          \(entries.joined(separator: ",\n          "))\n      ]"
    return """
      public var arguments: [PromptArgumentSpec] {
          \(raw: body)
      }
      """
  }

  private static func generateDefaultInit(_ arguments: [PromptArgumentInfo]) -> DeclSyntax {
    let needsInit = arguments.filter { !$0.hasDefault }
    if needsInit.isEmpty {
      return "public init() {}"
    }
    let assignments = needsInit.map { arg -> String in
      "self.\(arg.propertyName) = \(zeroLiteral(for: arg.swiftType))"
    }.joined(separator: "\n        ")
    return """
      public init() {
          \(raw: assignments)
      }
      """
  }

  private static func generateGetMessages(
    _ arguments: [PromptArgumentInfo], promptName: String
  ) -> DeclSyntax {
    let promptLiteral = literalString(promptName)
    let assigns = arguments.map { arg -> String in
      let key = literalString(arg.argumentName)
      let prop = arg.propertyName
      let base = baseSwiftType(arg.swiftType)
      let isOptional = arg.isOptional
      let isRequired = arg.isRequired && !arg.hasDefault

      // String is the raw arguments[key] value; other types parse from it.
      // Parenthesized closures below avoid the trailing-closure-confusable
      // warning when the non-optional branch wraps them in
      // `if let __v = <expr> { ... }`.
      let parseExpr: String
      let invalidReason: String
      switch base {
      case "String":
        parseExpr = "arguments[\(key)]"
        invalidReason = ""
      case "Bool":
        parseExpr = "arguments[\(key)].map({ $0.lowercased() == \"true\" })"
        invalidReason = "expected a string but got nothing to parse"
      case "Int":
        parseExpr = "arguments[\(key)].flatMap({ Int($0) })"
        invalidReason = "could not parse as Int"
      case "Double":
        parseExpr = "arguments[\(key)].flatMap({ Double($0) })"
        invalidReason = "could not parse as Double"
      case "Float":
        parseExpr = "arguments[\(key)].flatMap({ Float($0) })"
        invalidReason = "could not parse as Float"
      default:
        // Non-primitive fallback: assume RawRepresentable with String raw
        // value (e.g. `@Generable` String-raw enum).
        parseExpr = "arguments[\(key)].flatMap({ \(base)(rawValue: $0) })"
        invalidReason = "not a valid raw value for \(base)"
      }

      if isOptional {
        return "copy.\(prop) = \(parseExpr)"
      }

      // Required, non-optional, no default: validate the raw arguments[key]
      // exists first (distinguish "missing" from "invalid"), then parse.
      if base == "String" {
        return """
          guard let __v = arguments[\(key)] else {
                      throw FastMCPError.missingRequiredPromptArgument(prompt: \(promptLiteral), name: \(key))
                  }
                  copy.\(prop) = __v
          """
      }
      if isRequired {
        return """
          guard let __raw = arguments[\(key)] else {
                      throw FastMCPError.missingRequiredPromptArgument(prompt: \(promptLiteral), name: \(key))
                  }
                  guard let __v = \(parseExpr.replacingOccurrences(of: "arguments[\(key)]", with: "Optional.some(__raw)")) else {
                      throw FastMCPError.invalidPromptArgumentValue(prompt: \(promptLiteral), name: \(key), reason: \(literalString(invalidReason)))
                  }
                  copy.\(prop) = __v
          """
      }
      // Non-optional but has a default → absence is allowed (keeps default),
      // but if present-and-invalid, reject.
      return """
        if let __raw = arguments[\(key)] {
                    guard let __v = \(parseExpr.replacingOccurrences(of: "arguments[\(key)]", with: "Optional.some(__raw)")) else {
                        throw FastMCPError.invalidPromptArgumentValue(prompt: \(promptLiteral), name: \(key), reason: \(literalString(invalidReason)))
                    }
                    copy.\(prop) = __v
                }
        """
    }.joined(separator: "\n        ")

    let body =
      arguments.isEmpty
      ? "return try await getMessages()"
      : """
      var copy = self
              \(assigns)
              return try await copy.getMessages()
      """
    return """
      public func getMessages(arguments: [String: String]) async throws -> Messages {
          \(raw: body)
      }
      """
  }

  // MARK: - Helpers

  private static func baseSwiftType(_ swiftType: String) -> String {
    swiftType
      .replacingOccurrences(of: "Optional<", with: "")
      .replacingOccurrences(of: ">", with: "")
      .replacingOccurrences(of: "?", with: "")
      .trimmingCharacters(in: .whitespaces)
  }

  private static func zeroLiteral(for swiftType: String) -> String {
    let trimmed = swiftType.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("?") { return "nil" }
    switch baseSwiftType(trimmed) {
    case "String": return "\"\""
    case "Int": return "0"
    case "Double", "Float": return "0"
    case "Bool": return "false"
    default:
      if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { return "[]" }
      return "nil"
    }
  }

  private static func literalString(_ value: String) -> String {
    let escaped =
      value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
  }
}

struct PromptArgumentInfo {
  let propertyName: String
  let argumentName: String
  let description: String
  let swiftType: String
  let isOptional: Bool
  let isRequired: Bool
  let hasDefault: Bool
}

enum PromptMacroError: Error, CustomStringConvertible {
  case missingDescription
  case onlyApplicableToStruct

  var description: String {
    switch self {
    case .missingDescription: return "@MCPPrompt requires a description string"
    case .onlyApplicableToStruct: return "@MCPPrompt can only be applied to structs"
    }
  }
}
