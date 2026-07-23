import CoachLLM
import Core
import Foundation
import Testing

@Suite("MethodologyLibrary")
struct MethodologyLibraryTests {
    @Test("fixture decodes placeholder seed")
    func fixtureDecode() throws {
        let url = try #require(Bundle.module.url(forResource: "methodology_seed", withExtension: "json"))
        let document = try MethodologyLibrary.load(from: url)

        #expect(document.placeholder)
        #expect(document.seedVersion == 1)
        #expect(document.evidence.count == 1)
        #expect(document.topics.count == 1)
        #expect(document.evidence(for: ["ev-volume-landmarks"]).first?.id == "ev-volume-landmarks")
    }
}
