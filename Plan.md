# FastMCP Refactoring Plan

## Summary
Refactor FastMCP library to improve code organization, add integration tests, and follow naming conventions.

---

## Decisions from Interview

### Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Shutdown Control | Automatic only | ServiceLifecycle handles everything - simpler API |
| Internal Access Level | True internal | FastMCPService hidden from users, cleaner public API |
| Import Name | Keep `import FastMCP` | Cleaner imports, folder name is just organization |
| Log Format | Basic logger | Users can configure their own handler |
| Extraction Scope | Full separation | Service, Capabilities, and future internal helpers |
| Example Naming | Keep simple names | Example, ExampleTools - short and clear |
| Dedup Logic | Extract to helper | ToolDeduplicator struct with strategy pattern |
| Test Scope | Add integration tests | Mock transport, send MCP messages, verify responses |
| File Naming | Descriptive names | Service.swift, Capabilities.swift - clear purpose |
| Test Approach | Mock transport | Fast, deterministic tests with TestTransport |
| Response Processing | Leave to users | Keep library focused on server infrastructure |

---

## Folder Structure (Target)

```
swift-fast-mcp/
├── Package.swift
├── .gitignore
├── Plan.md
├── Sources/
│   ├── swift-fast-mcp/           # Main library (import FastMCP)
│   │   ├── FastMCP.swift         # Public API: FastMCP.builder()
│   │   ├── Transport.swift       # Public: Transport enum
│   │   ├── FastMCPError.swift    # Public: Error types
│   │   ├── Exports.swift         # Re-exports MCPToolkit, MCP, etc.
│   │   └── Internal/             # Internal implementation details
│   │       ├── Service.swift     # FastMCPService (internal)
│   │       ├── Capabilities.swift # CapabilitiesBuilder (internal)
│   │       └── Deduplicator.swift # ToolDeduplicator with strategy (internal)
│   ├── ExampleTools/             # Shared example tools
│   │   ├── WeatherTool.swift
│   │   ├── MathTool.swift
│   │   └── GreetingTool.swift
│   └── Example/                  # Example executable
│       └── main.swift
└── Tests/
    └── swift-fast-mcp-tests/
        ├── BuilderTests.swift    # Builder API tests
        ├── IntegrationTests.swift # Server integration tests
        └── Mocks/
            └── TestTransport.swift # Mock transport for testing
```

---

## Tasks

### Phase 1: Folder Restructuring (DONE)
- [x] Rename Sources/FastMCP → Sources/swift-fast-mcp
- [x] Rename Tests/FastMCPTests → Tests/swift-fast-mcp-tests
- [x] Create Internal folder
- [x] Update Package.swift with new paths

### Phase 2: Internal Components Extraction (DONE)
- [x] Create Internal/Service.swift
  - Move FastMCPService struct from FastMCP.swift
  - Mark as `internal` access level
  - Keep same implementation

- [x] Create Internal/Capabilities.swift
  - Extract Server.Capabilities construction logic
  - Create CapabilitiesBuilder internal struct
  - Handle resources/tools capability flags

- [x] Create Internal/Deduplicator.swift
  - Create ToolDeduplicator struct (simple keepFirst behavior)
  - Create ResourceDeduplicator struct (simple keepFirst behavior)
  - No throwing, no strategy pattern - KISS principle

### Phase 3: Refactor FastMCP.swift (DONE)
- [x] Import internal components
- [x] Use CapabilitiesBuilder for capability construction
- [x] Use ToolDeduplicator for tool deduplication
- [x] Use ResourceDeduplicator for resource deduplication
- [x] Keep Builder struct public with same API

### Phase 4: Integration Tests (DONE)
- [x] Use MCP's built-in InMemoryTransport instead of custom TestTransport
  - Creates connected pair of transports for client-server testing
  - No custom implementation needed

- [x] Create IntegrationTests.swift (6 tests)
  - Test server responds to tool list request
  - Test server executes tool correctly
  - Test server with no capabilities handles gracefully
  - Test server handles greeting tool
  - Test server handles weather tool
  - Test server with multiple tools

### Phase 5: Verification (DONE)
- [x] Run `swift build` - all targets compile
- [x] Run `swift test` - all 16 tests pass (10 Builder + 6 Integration)
- [x] Run `swift build --target Example` - example compiles
- [x] `import FastMCP` still works

---

## Internal Component Specifications

### Service.swift

```swift
// Internal/Service.swift
import Foundation
import Logging
import MCP
import ServiceLifecycle

struct FastMCPService: Service, Sendable {
  let server: Server
  let transport: MCP.Transport
  let logger: Logger
  let onStart: (@Sendable () async -> Void)?
  let onShutdown: (@Sendable () async -> Void)?

  func run() async throws {
    // ... implementation
  }
}
```

### Capabilities.swift

```swift
// Internal/Capabilities.swift
import MCP

struct CapabilitiesBuilder: Sendable {
  static func build(
    hasTools: Bool,
    hasResources: Bool
  ) -> Server.Capabilities {
    // ... implementation
  }
}
```

### Deduplicator.swift

```swift
// Internal/Deduplicator.swift
import MCPToolkit

struct ToolDeduplicator: Sendable {
  func deduplicate(_ existing: [any MCPTool], adding new: [any MCPTool]) -> [any MCPTool] {
    var result = existing
    let existingNames = Set(existing.map { $0.name })
    for tool in new where !existingNames.contains(tool.name) {
      result.append(tool)
    }
    return result
  }
}

struct ResourceDeduplicator: Sendable {
  func deduplicate(_ existing: [any MCPResource], adding new: [any MCPResource]) -> [any MCPResource] {
    var result = existing
    let existingURIs = Set(existing.map { $0.uri })
    for resource in new where !existingURIs.contains(resource.uri) {
      result.append(resource)
    }
    return result
  }
}
```

### TestTransport.swift

```swift
// Mocks/TestTransport.swift
import MCP

final class TestTransport: MCP.Transport, @unchecked Sendable {
  var sentMessages: [Data] = []
  var responseQueue: [Data] = []
  var isConnected: Bool = false

  func send(_ data: Data) async throws {
    sentMessages.append(data)
  }

  func receive() async throws -> Data {
    // Return queued response or wait
  }

  func connect() async throws {
    isConnected = true
  }

  func disconnect() async throws {
    isConnected = false
  }
}
```

---

## API Surface (No Changes)

The public API remains unchanged:

```swift
import FastMCP

@main
struct MyServer {
  static func main() async throws {
    try await FastMCP.builder()
      .name("My Server")
      .version("1.0.0")
      .addTools([MyTool()])
      .addResources([MyResource()])
      .transport(.stdio)
      .logLevel(.info)
      .shutdownSignals([.sigterm, .sigint])
      .onStart { }
      .onShutdown { }
      .run()
  }
}
```

---

## Status

**Current Phase**: ALL PHASES COMPLETE ✅

**Completed**:
- Phase 1: Folder restructuring
- Phase 2: Internal components extraction (Service, Capabilities, Deduplicator)
- Phase 3: FastMCP.swift refactored to use internal components
- Phase 4: Integration tests with InMemoryTransport (6 tests)
- Phase 5: Verification - all 16 tests pass, all targets build

**Final Structure**:
```
Sources/swift-fast-mcp/
├── FastMCP.swift           # Public API
├── Transport.swift         # Public Transport enum
├── FastMCPError.swift      # Public error types
├── Exports.swift           # Re-exports
└── Internal/
    ├── Service.swift       # FastMCPService
    ├── Capabilities.swift  # CapabilitiesBuilder
    └── Deduplicator.swift  # Tool/Resource deduplicators
```
