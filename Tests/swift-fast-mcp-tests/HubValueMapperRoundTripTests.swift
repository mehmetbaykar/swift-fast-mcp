import FastMCPAIBridge
import Foundation
import MCP
import SwiftAIHub
import Testing

@Suite("HubValueMapper round-trip")
struct HubValueMapperRoundTripTests {
  @Test(".data(mime, bytes) round-trips through GeneratedContent")
  func dataWithMimeRoundTrips() {
    let bytes = Data([0xCA, 0xFE, 0xBA, 0xBE])
    let original: Value = .data(mimeType: "image/png", bytes)
    let gen = HubValueMapper.generatedContent(from: original)
    let back = HubValueMapper.value(from: gen)
    guard case .data(let mime, let restored) = back else {
      Issue.record("expected .data, got \(back)")
      return
    }
    #expect(mime == "image/png")
    #expect(restored == bytes)
  }

  @Test(".data with nil mime round-trips")
  func dataWithoutMimeRoundTrips() {
    let bytes = Data([0x01, 0x02, 0x03])
    let original: Value = .data(mimeType: nil, bytes)
    let back = HubValueMapper.value(from: HubValueMapper.generatedContent(from: original))
    guard case .data(let mime, let restored) = back else {
      Issue.record("expected .data, got \(back)")
      return
    }
    #expect(mime == nil)
    #expect(restored == bytes)
  }

  @Test("plain strings pass through unchanged")
  func plainStringPassThrough() {
    let gen = GeneratedContent(kind: .string("hello world"))
    #expect(HubValueMapper.value(from: gen) == .string("hello world"))
  }

  @Test("strings shaped like data: URL but with invalid base64 stay as strings")
  func malformedDataURLStaysString() {
    // "***" is not valid base64 — decoder should refuse and fall through.
    let gen = GeneratedContent(kind: .string("data:image/png;base64,***"))
    #expect(HubValueMapper.value(from: gen) == .string("data:image/png;base64,***"))
  }
}
