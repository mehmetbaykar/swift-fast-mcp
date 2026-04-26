// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "swift-fast-mcp",
  platforms: [
    .macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1),
  ],
  products: [
    .library(name: "FastMCP", targets: ["FastMCP"]),
    .library(name: "FastMCPAIBridge", targets: ["FastMCPAIBridge"]),
    .executable(name: "Example", targets: ["Example"]),
  ],
  dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.0"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.9.1"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
    .package(url: "https://github.com/mehmetbaykar/swift-ai-hub", from: "0.6.1"),
  ],
  targets: [
    .macro(
      name: "FastMCPMacros",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "FastMCPAIBridge",
      dependencies: [
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "SwiftAIHub", package: "swift-ai-hub"),
      ],
      path: "Sources/FastMCPAIBridge"
    ),
    .target(
      name: "FastMCP",
      dependencies: [
        "FastMCPAIBridge",
        "FastMCPMacros",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        .product(name: "UnixSignals", package: "swift-service-lifecycle"),
        .product(name: "SwiftAIHub", package: "swift-ai-hub"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      path: "Sources/swift-fast-mcp"
    ),
    .target(name: "ExampleTools", dependencies: ["FastMCP"]),
    .executableTarget(name: "Example", dependencies: ["FastMCP", "ExampleTools"]),
    .testTarget(
      name: "swift-fast-mcp-tests",
      dependencies: ["FastMCP", "ExampleTools"],
      path: "Tests/swift-fast-mcp-tests"
    ),
  ]
)
