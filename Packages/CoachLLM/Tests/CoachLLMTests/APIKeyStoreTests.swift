import Foundation
import Testing
@testable import CoachLLM

@Suite("APIKeyStore")
struct APIKeyStoreTests {
    private func makeStore() -> APIKeyStore {
        APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
    }

    @Test("round-trips a key")
    func roundTrip() throws {
        let store = makeStore()
        try store.save("test-key-value", kind: .gemini)

        let loaded = try store.load(kind: .gemini)
        #expect(loaded == "test-key-value")
        #expect(store.hasKey(kind: .gemini))
    }

    @Test("load returns nil when missing")
    func missingKey() throws {
        let store = makeStore()
        #expect(try store.load(kind: .gemini) == nil)
        #expect(store.hasKey(kind: .gemini) == false)
    }

    @Test("delete removes a stored key")
    func deleteKey() throws {
        let store = makeStore()
        try store.save("temporary", kind: .gemini)
        try store.delete(kind: .gemini)

        #expect(try store.load(kind: .gemini) == nil)
    }

    @Test("save overwrites an existing key")
    func overwrite() throws {
        let store = makeStore()
        try store.save("first", kind: .gemini)
        try store.save("second", kind: .gemini)

        #expect(try store.load(kind: .gemini) == "second")
    }

    @Test("displayValue never returns the raw key")
    func masksDisplayValue() throws {
        let store = makeStore()
        try store.save("sk-abcdefghijklmnopqrstuvwxyz", kind: .gemini)
        let displayed = store.displayValue(for: .gemini)
        #expect(displayed.hasPrefix("••••"))
        #expect(!displayed.contains("sk-abcdefghijklmnopqrstuvwxyz"))
        #expect(displayed.hasSuffix("wxyz"))
    }

    @Test("rejects empty values")
    func rejectsEmptyValue() throws {
        let store = makeStore()
        #expect(throws: APIKeyStoreError.invalidData) {
            try store.save("", kind: .gemini)
        }
    }
}
