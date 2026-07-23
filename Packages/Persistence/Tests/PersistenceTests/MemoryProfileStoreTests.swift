import CoachLLM
import Core
import Foundation
import Testing
@testable import Persistence

@Suite("MemoryProfile store")
struct MemoryProfileStoreTests {
    @Test("round trip persistence")
    func roundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let profile = MemoryProfile(
            baselinesSummary: "Sleep need ~7.5 h.",
            mesocyclePosition: "Deload week for upper body.",
            phaseGoal: PhaseGoal(phase: .cut, weeklyRateKg: 0.5),
            preferences: "Evening sessions only.",
            standingConstraints: "Avoid deep knee flexion.",
            whatHasWorked: "Higher protein on rest days."
        )

        try store.memoryProfile.save(profile)
        let loaded = try store.memoryProfile.load()

        #expect(loaded == profile)
    }

    @Test("load returns empty when unset")
    func loadEmptyDefault() throws {
        let store = try PersistenceStore.inMemory()
        #expect(try store.memoryProfile.load() == .empty)
    }

    @Test("save overwrites prior profile")
    func saveOverwrites() throws {
        let store = try PersistenceStore.inMemory()
        try store.memoryProfile.save(MemoryProfile(preferences: "First"))
        try store.memoryProfile.save(MemoryProfile(preferences: "Second"))

        let loaded = try store.memoryProfile.load()
        #expect(loaded.preferences == "Second")
    }
}
