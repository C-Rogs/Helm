import Foundation
import Testing
@testable import CoachLLM

@Suite("Gemini structured output")
struct GeminiStructuredDecodeTests {
    private func fixtureText(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            Issue.record("Missing fixture \(name).json")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("session adjustment fixture decodes with schema stamp")
    func sessionAdjustmentV1() throws {
        let json = try fixtureText(named: "session_adjustment_v1")
        let payload = try CoachStructuredOutputDecoder.decode(
            SessionAdjustmentPayload.self,
            from: json,
            expectedSchema: .sessionAdjustmentV1
        )
        #expect(payload.operations.count == 1)
        #expect(payload.operations[0].kind == .swap)
        #expect(payload.operations[0].toExerciseID == "db-fly")
    }

    @Test("schema version mismatch is a typed error")
    func schemaMismatch() throws {
        let json = try fixtureText(named: "session_adjustment_wrong_schema")
        do {
            _ = try CoachStructuredOutputDecoder.decode(
                SessionAdjustmentPayload.self,
                from: json,
                expectedSchema: .sessionAdjustmentV1
            )
            Issue.record("Expected schema mismatch")
        } catch let error as CoachStructuredOutputError {
            #expect(error == .schemaVersionMismatch(
                expected: CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue,
                found: "session_adjustment.v0"
            ))
        }
    }

    @Test("meal estimate fixture decodes")
    func mealEstimateV1() throws {
        let json = try fixtureText(named: "meal_estimate_v1")
        let payload = try CoachStructuredOutputDecoder.decode(
            MealEstimatePayload.self,
            from: json,
            expectedSchema: .mealEstimateV1
        )
        #expect(payload.caloriesKcal == 650)
        #expect(payload.confidence == .medium)
    }

    @Test("morning brief fixture decodes")
    func morningBriefV1() throws {
        let json = try fixtureText(named: "morning_brief_v1")
        let payload = try CoachStructuredOutputDecoder.decode(
            MorningBriefPayload.self,
            from: json,
            expectedSchema: .briefV1
        )
        #expect(payload.narration.contains("ARC 72"))
        #expect(payload.citationIDs == ["ev-chest-1"])
    }
}

@Suite("GeminiProvider fixtures")
struct GeminiProviderFixtureTests {
    private func fixtureKeyStore() -> APIKeyStore {
        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try? store.delete(kind: .gemini)
        try! store.save("fixture-key", kind: .gemini)
        return store
    }


    @Test("fixture stream reassembles and tracks request id")
    func streamFixture() async throws {
        let client = FixtureGeminiHTTPClient(bundle: .module)
        let store = fixtureKeyStore()
        let provider = GeminiProvider(apiKeyStore: store, httpClient: client)

        await GeminiStreamTracer.shared.reset()

        let stream = try await provider.respond(
            systemInstructions: "system",
            contextBlock: "context",
            userMessage: "How is readiness?",
            thread: .empty
        )

        let text = try await FixtureStreamHarness.reassemble(stream)
        #expect(text == "Readiness is steady.")
        #expect(client.lastStreamRequestID != nil)

        let spans = await GeminiStreamTracer.shared.completedSpans()
        #expect(spans.contains { $0.name == "GeminiStream" && $0.began && $0.ended })
    }

    @Test("fixture generate decodes session adjustment artefact")
    func generateSessionAdjustmentFixture() async throws {
        let client = FixtureGeminiHTTPClient(bundle: .module)
        let store = fixtureKeyStore()
        let provider = GeminiProvider(apiKeyStore: store, httpClient: client)

        let artefact = try await provider.generateSessionAdjustment(
            systemInstructions: "system",
            contextBlock: "context",
            userMessage: "Swap the fly",
            thread: .empty
        )

        #expect(artefact.schemaVersion == .sessionAdjustmentV1)
        #expect(artefact.promptVersion == .sessionAdjustmentV1)
        #expect(artefact.payload.operations.count == 1)
        #expect(client.lastGenerateRequestID != nil)
    }
}

@Suite("CoachLLM redaction")
struct CoachLLMRedactionTests {
    @Test("sources avoid logging Gemini request URLs")
    func grepSourcesForRequestURLs() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CoachLLM", isDirectory: true)

        let forbidden = [
            "generativelanguage.googleapis.com",
            "absoluteString",
            "urlRequest.url",
            "requestURL"
        ]

        let loggerMarkers = ["Logger(", "helmLogger(", "os_signpost", "DiagnosticsLog", "record("]

        var violations: [String] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        for case let file as URL in enumerator {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() {
                let lineText = String(line)
                guard forbidden.contains(where: { lineText.contains($0) }) else { continue }
                if loggerMarkers.contains(where: { lineText.contains($0) }) {
                    violations.append("\(file.lastPathComponent):\(index + 1): \(lineText)")
                }
            }
        }

        #expect(violations.isEmpty, "Found URL leakage: \(violations.joined(separator: "; "))")
    }
}

@Suite("ProviderPreferencesStore")
struct ProviderPreferencesStoreTests {
    @Test("selected provider round trips in user defaults")
    func roundTrip() {
        let suiteName = "CoachLLMTests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProviderPreferencesStore(defaults: defaults)
        store.selectedProvider = .openRouter
        #expect(store.selectedProvider == .openRouter)

        let reloaded = ProviderPreferencesStore(defaults: defaults)
        #expect(reloaded.selectedProvider == .openRouter)
    }
}
