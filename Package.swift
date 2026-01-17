// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "swift-fast-mcp",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "FastMCP",
      targets: ["FastMCP"]
    ),
    .executable(
      name: "Example",
      targets: ["Example"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.10.2"),
    .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.9.1"),
    .package(url: "https://github.com/mehmetbaykar/swift-mcp-toolkit.git", from: "0.2.1"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
  ],
  targets: [
    .target(
      name: "FastMCP",
      dependencies: [
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
        .product(name: "UnixSignals", package: "swift-service-lifecycle"),
        .product(name: "MCPToolkit", package: "swift-mcp-toolkit"),
        .product(name: "Logging", package: "swift-log"),
      ],
      path: "Sources/swift-fast-mcp"
    ),
    .target(
      name: "ExampleTools",
      dependencies: ["FastMCP"]
    ),
    .executableTarget(
      name: "Example",
      dependencies: ["FastMCP", "ExampleTools"]
    ),
    .testTarget(
      name: "swift-fast-mcp-tests",
      dependencies: ["FastMCP", "ExampleTools"],
      path: "Tests/swift-fast-mcp-tests"
    ),
  ]
)
