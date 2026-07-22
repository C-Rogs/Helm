import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Workout text parser")
struct WorkoutTextParserTests {
    private static let cleanSample = """
        FRIDAY EMERGENCY PUMP (Low Fatigue)

        Wide-Grip Lat Pulldown (Upper Lat Flush)
        Set 1: 45 kg x 12 (Warm-up)
        Set 2: 54 kg x 10 @ 7 RPE
        Set 3: 54 kg x 10 @ 8 RPE (Stop 2 reps short of failure)

        Machine Chest Press (Supported Pectoral Drive)
        Set 1: 40 kg x 12 (Warm-up)
        Set 2: 60 kg x 8 @ 7.5 RPE
        """

    private static let messySample = """
        PUSH DAY!!!

        Bench Press
        Not a set line
        Set 1: 100 kg x 5
        100 kg x 5 @8

        Squat (Barbell): 3 x 5 @ 100kg
        """

    private static let partialSample = """
        UPPER

        Mystery Movement
        Set 1: 20 kg x 12

        Pull Up
        x 10
        x 8
        """

    @Test("clean pasted day parses title, exercises, warmups, and notes")
    func cleanSampleParses() {
        let parsed = WorkoutTextParser.parse(Self.cleanSample)
        #expect(parsed.title == "FRIDAY EMERGENCY PUMP (Low Fatigue)")
        #expect(parsed.exercises.count == 2)
        #expect(parsed.exercises[0].exerciseTitle == "Wide-Grip Lat Pulldown (Upper Lat Flush)")
        #expect(parsed.exercises[0].sets.count == 3)
        #expect(parsed.exercises[0].sets[0].setType == .warmup)
        #expect(parsed.exercises[0].sets[1].rpe == 7)
        #expect(parsed.exercises[0].sets[2].prescriptionNote == "Stop 2 reps short of failure")
        #expect(parsed.exercises[1].sets[1].rpe == 7.5)
    }

    @Test("messy text skips bad lines and parses compressed exercise summaries")
    func messySampleParses() {
        let parsed = WorkoutTextParser.parse(Self.messySample)
        #expect(parsed.title == "PUSH DAY!!!")
        #expect(parsed.skippedLines.contains("Not a set line"))
        #expect(parsed.exercises.count == 2)
        #expect(parsed.exercises[0].exerciseTitle == "Bench Press")
        #expect(parsed.exercises[0].sets.count == 2)
        #expect(parsed.exercises[1].exerciseTitle == "Squat (Barbell)")
        #expect(parsed.exercises[1].sets.count == 3)
        #expect(parsed.exercises[1].sets[0].mass?.kilograms == 100)
        #expect(parsed.exercises[1].sets[0].reps == 5)
    }

    @Test("partial sample parses bodyweight sets without load")
    func partialBodyweightParses() {
        let parsed = WorkoutTextParser.parse(Self.partialSample)
        #expect(parsed.exercises.count == 2)
        #expect(parsed.exercises[1].exerciseTitle == "Pull Up")
        #expect(parsed.exercises[1].sets.count == 2)
        #expect(parsed.exercises[1].sets[0].mass == nil)
        #expect(parsed.exercises[1].sets[0].reps == 10)
        #expect(parsed.exercises[1].sets[0].setType == .bodyweight)
    }

    @Test("lb conversion")
    func lbConversion() {
        let parsed = WorkoutTextParser.parse("""
            LEG DAY

            Squat
            Set 1: 225 lb x 5
            """)
        let weight = parsed.exercises.first?.sets.first?.mass?.kilograms
        #expect(weight != nil)
        #expect(abs((weight ?? 0) - (225 * 0.45359237)) < 0.01)
    }

    @Test("empty string returns empty workout")
    func emptyString() {
        let parsed = WorkoutTextParser.parse("")
        #expect(parsed.exercises.isEmpty)
        #expect(parsed.title == "Workout")
    }

    @Test("rest lines attach to exercise or prior set")
    func restLines() {
        let parsed = WorkoutTextParser.parse("""
            LEGS

            Squat
            Set 1: 100 kg x 5
            Rest 60s
            Set 2: 100 kg x 5
            Rest: 90s

            Leg Press
            Set 1: 200 kg x 10
            """)
        #expect(parsed.exercises[0].sets[0].restDurationSeconds == 60)
        #expect(parsed.exercises[0].restDurationSeconds == 90)
    }
}

@Suite("Workout import")
struct WorkoutImportTests {
  private let benchPressID = "exercise-bench-press"
  private let squatID = "exercise-squat"

    private func makeStore() throws -> PersistenceStore {
        try PersistenceStore.inMemory()
    }

    private func seedExercises(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.addAlias(
            id: "alias-bench",
            exerciseID: benchPressID,
            alias: "Bench Press"
        )
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat (barbell)",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "quads"
        )
    }

    @Test("resolver matches alias and display names")
    func resolverMatches() throws {
        let store = try makeStore()
        try seedExercises(in: store)

        let parsed = WorkoutTextParser.parse("""
            PUSH

            Bench Press
            Set 1: 80 kg x 8

            Squat (Barbell)
            Set 1: 100 kg x 5
            """)

        let resolver = WorkoutImportResolver(exercises: store.exercises)
        let resolutions = try resolver.resolve(parsed: parsed)

        #expect(resolutions.count == 2)
        #expect(resolutions[0].exerciseID == benchPressID)
        #expect(resolutions[0].matchKind == .alias)
        #expect(resolutions[1].exerciseID == squatID)
        #expect(resolutions[1].matchKind == .displayName)
    }

    @Test("unresolved exercises surface for manual mapping")
    func unresolvedExercises() throws {
        let store = try makeStore()
        try seedExercises(in: store)

        let parsed = WorkoutTextParser.parse("""
            LEGS

            Mystery Curl
            Set 1: 20 kg x 12
            """)

        let resolver = WorkoutImportResolver(exercises: store.exercises)
        let resolutions = try resolver.resolve(parsed: parsed)

        #expect(resolutions.count == 1)
        #expect(resolutions[0].matchKind == .unresolved)
        #expect(resolutions[0].exerciseID == nil)
    }

    @Test("imported sessions appear in history and aliases persist")
    func importToHistory() throws {
        let store = try makeStore()
        try seedExercises(in: store)

        let parsed = WorkoutTextParser.parse("""
            PUSH

            Bench Press
            Set 1: 80 kg x 8
            Set 2: 85 kg x 6
            """)

        let service = WorkoutImportService(
            sessions: store.workoutSessions,
            exercises: store.exercises,
            personalRecords: store.personalRecords
        )

        let result = try service.importToHistory(
            parsed: parsed,
            mappings: ["Bench Press": benchPressID],
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(result.session.status == .completed)
        #expect(result.session.source == .importSource)

        let summaries = try store.workoutSessions.listSummaries(limit: 10)
        #expect(summaries.count == 1)
        #expect(summaries[0].title == "PUSH")
        #expect(summaries[0].totalSetCount == 2)

        let fetched = try store.workoutSessions.fetch(id: result.session.id)
        #expect(fetched?.exercises.count == 1)
        #expect(fetched?.exercises[0].sets.count == 2)

        let remapped = try store.exercises.resolveImportedTitle("Bench Press")
        #expect(remapped?.exerciseID == benchPressID)
    }
}
