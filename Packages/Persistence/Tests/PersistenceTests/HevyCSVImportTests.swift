import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Hevy CSV import")
struct HevyCSVImportTests {
    private let benchPressID = "ex-bench"
    private let pullUpID = "ex-pullup"
    private let squatID = "ex-squat"

    @Test("parses kg CSV, clips old sessions, skips cardio, maps set types")
    func parseKgSample() throws {
        let csv = try loadFixture("hevy_export_sample.csv")
        let result = try HevyCSVParser.parse(
            csvText: csv,
            lookbackDays: 90,
            referenceNow: date("20 Jan 2026, 18:00")
        )

        #expect(result.clippedAwaySessionCount == 1)
        #expect(result.skippedCardioSetCount == 1)
        #expect(result.sessions.count == 2)
        #expect(result.totalSetCount == 6)
        #expect(result.uniqueExerciseTitles.contains("Mystery Machine Fly"))

        let push = try #require(result.sessions.first { $0.title == "Push Day" })
        #expect(push.exercises.count == 2)
        #expect(push.exercises[0].sets[0].setType == .warmup)
        #expect(push.exercises[0].sets[1].mass?.kilograms == 100)
        #expect(push.id.hasPrefix("hevy-"))
    }

    @Test("parses lbs CSV and converts mass to kilograms")
    func parseLbsSample() throws {
        let csv = try loadFixture("hevy_export_lbs.csv")
        let result = try HevyCSVParser.parse(csvText: csv, lookbackDays: 90)

        #expect(result.sessions.count == 1)
        let squat = try #require(result.sessions[0].exercises.first)
        #expect(squat.sets[0].setType == .normal)
        #expect(squat.sets[1].setType == .dropSet)
        let kg = try #require(squat.sets[0].mass?.kilograms)
        #expect(abs(kg - Mass(pounds: 225).kilograms) < 0.01)
    }

    @Test("bulk import writes completed sessions, aliases, and is idempotent")
    func bulkImportIdempotent() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)

        let csv = try loadFixture("hevy_export_sample.csv")
        let parsed = try HevyCSVParser.parse(
            csvText: csv,
            lookbackDays: 90,
            referenceNow: date("20 Jan 2026, 18:00")
        )

        let resolver = WorkoutImportResolver(exercises: store.exercises)
        var resolutions = try resolver.resolve(titles: parsed.uniqueExerciseTitles)
        #expect(resolutions.contains { $0.importedTitle == "Mystery Machine Fly" && !$0.isResolved })

        let service = WorkoutImportService(
            sessions: store.workoutSessions,
            exercises: store.exercises,
            personalRecords: store.personalRecords
        )

        let mappings = [
            "Bench Press (Barbell)": benchPressID,
            "Pull Up": pullUpID,
            "Mystery Machine Fly": benchPressID
        ]
        resolutions = try resolver.resolve(titles: parsed.uniqueExerciseTitles, manualMappings: mappings)
        #expect(resolutions.allSatisfy { $0.isResolved })

        let first = try service.importHevySessions(parsed.sessions, mappings: mappings)
        #expect(first.importedSessionCount == 2)
        #expect(first.importedSetCount == 6)
        #expect(first.skippedDuplicateCount == 0)

        let second = try service.importHevySessions(parsed.sessions, mappings: mappings)
        #expect(second.importedSessionCount == 0)
        #expect(second.skippedDuplicateCount == 2)

        let summaries = try store.workoutSessions.listSummaries(limit: 10)
        #expect(summaries.count == 2)

        let remapped = try store.exercises.resolveImportedTitle("Mystery Machine Fly")
        #expect(remapped?.exerciseID == benchPressID)

        let push = try #require(parsed.sessions.first { $0.title == "Push Day" })
        let fetched = try store.workoutSessions.fetch(id: push.id)
        #expect(fetched?.status == .completed)
        #expect(fetched?.source == .importSource)
        #expect(fetched?.exercises.first?.sets.contains { $0.mass?.kilograms == 100 } == true)
    }

    private func loadFixture(_ name: String) throws -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let url = try #require(Bundle.module.url(forResource: base, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func date(_ hevy: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.date(from: hevy)!
    }

    private func seedExercises(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press barbell",
            displayName: "Bench Press (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest",
            isPickerDefault: true
        )
        try store.exercises.upsert(
            id: pullUpID,
            canonicalName: "pull up",
            displayName: "Pull Up",
            exerciseMode: .bodyweightReps,
            primaryMuscleGroup: "back",
            isPickerDefault: true
        )
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat barbell",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "quads",
            isPickerDefault: true
        )
        try store.exercises.addAlias(id: "alias-bench", exerciseID: benchPressID, alias: "Bench Press (Barbell)")
        try store.exercises.addAlias(id: "alias-pull", exerciseID: pullUpID, alias: "Pull Up")
    }
}
