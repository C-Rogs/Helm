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

    private static let mondayPushPrescription = """
        🏋️ Monday: Push (Shoulder & Tricep Focus)
        Bodyweight Baseline: ~72.5 kg

        Warm-up: 5 mins light cardio + shoulder rotations

        [ ] Dumbbell Shoulder Press (Heavy)
            • Target Weight: 18 kg – 22 kg per DB
            • Sets: 3 x 8 reps
            • Intensity: RPE 8–9 (1–2 reps in the tank)
            • Rest: 2 mins

        [ ] Incline Dumbbell Bench Press
            • Target Weight: 20 kg – 26 kg per DB
            • Sets: 3 x 8–10 reps
            • Intensity: RPE 8
            • Rest: 90 secs

        [ ] Cable / DB Lateral Raises (Side Delts)
            • Target Weight: 5 kg – 9 kg
            • Sets: 3 x 12–15 reps
            • Intensity: RPE 8–9 (Strict form, no swinging)
            • Rest: 60 secs

        [ ] Dips (or Deficit Push-Ups)
            • Target Weight: Bodyweight (~72.5 kg) [Add +5–10 kg belt if easy]
            • Sets: 3 x to near-failure
            • Intensity: RPE 9
            • Rest: 90 secs

        [ ] Overhead Cable Tricep Extension (Long Head)
            • Target Weight: 17.5 kg – 25 kg
            • Sets: 3 x 10–12 reps
            • Intensity: RPE 8
            • Rest: 60 secs

        [ ] Tricep Rope Pushdowns
            • Target Weight: 20 kg – 27.5 kg
            • Sets: 3 x 12–15 reps (+ Drop set on set 3)
            • Intensity: RPE 9 (Full burn)
            • Rest: 60 secs
        """

    @Test("planner checklist prescription parses exercises with range midpoints")
    func prescriptionChecklistParses() {
        let parsed = WorkoutTextParser.parse(Self.mondayPushPrescription)
        #expect(parsed.title == "Monday: Push (Shoulder & Tricep Focus)")
        #expect(parsed.exercises.count == 6)
        #expect(parsed.skippedLines.contains("Bodyweight Baseline: ~72.5 kg"))
        #expect(parsed.skippedLines.contains("Warm-up: 5 mins light cardio + shoulder rotations"))

        let shoulderPress = parsed.exercises[0]
        #expect(shoulderPress.exerciseTitle == "Dumbbell Shoulder Press (Heavy)")
        #expect(shoulderPress.sets.count == 3)
        #expect(shoulderPress.sets[0].reps == 8)
        #expect(shoulderPress.sets[0].mass?.kilograms == 20)
        #expect(shoulderPress.sets[0].rpe == 8.5)
        #expect(shoulderPress.restDurationSeconds == 120)
        #expect(shoulderPress.sets[0].prescriptionNote?.contains("per DB") == true)

        let inclineBench = parsed.exercises[1]
        #expect(inclineBench.sets[0].mass?.kilograms == 23)
        #expect(inclineBench.sets[0].reps == 9)
        #expect(inclineBench.sets[0].rpe == 8)
        #expect(inclineBench.restDurationSeconds == 90)

        let lateralRaises = parsed.exercises[2]
        #expect(lateralRaises.sets[0].mass?.kilograms == 7)
        #expect(lateralRaises.sets[0].reps == 13)
        #expect(lateralRaises.sets[0].rpe == 8.5)

        let dips = parsed.exercises[3]
        #expect(dips.sets[0].setType == .bodyweight)
        #expect(dips.sets[0].mass == nil)
        #expect(dips.sets[0].reps == 12)
        #expect(dips.sets[0].rpe == 9)

        let tricepExtension = parsed.exercises[4]
        #expect(tricepExtension.sets[0].mass?.kilograms == 21.25)
        #expect(tricepExtension.sets[0].reps == 11)

        let pushdowns = parsed.exercises[5]
        #expect(pushdowns.sets[0].mass?.kilograms == 23.75)
        #expect(pushdowns.sets[0].reps == 13)
        #expect(pushdowns.sets[0].prescriptionNote?.contains("Drop set") == true)
    }

    @Test("hevy format still parses when checklist markers absent")
    func hevyFormatUnchanged() {
        let parsed = WorkoutTextParser.parse(Self.cleanSample)
        #expect(parsed.exercises.count == 2)
        #expect(parsed.exercises[0].sets.count == 3)
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

    @Test("build plan and start active session with planned sets")
    func startImportedPlan() throws {
        let store = try makeStore()
        try seedExercises(in: store)

        let parsed = WorkoutTextParser.parse("""
            PUSH

            Bench Press
            Set 1: 80 kg x 8 @ 8 RPE
            Set 2: 85 kg x 6 @ 8.5 RPE
            Set 3: 85 kg x 6 @ 9 RPE
            """)

        let service = WorkoutImportService(
            sessions: store.workoutSessions,
            exercises: store.exercises,
            personalRecords: store.personalRecords
        )

        let plan = try service.buildPlan(
            parsed: parsed,
            mappings: ["Bench Press": benchPressID]
        )
        #expect(plan.title == "PUSH")
        #expect(plan.exercises.count == 1)
        #expect(plan.exercises[0].sets.count == 3)
        #expect(plan.exercises[0].sets[0].mass?.kilograms == 80)
        #expect(plan.exercises[0].sets[0].rpe == 8)

        let template = try service.buildTemplate(
            parsed: parsed,
            mappings: ["Bench Press": benchPressID]
        )
        #expect(template.name == "PUSH")
        #expect(template.exercises.count == 1)
        #expect(template.exercises[0].targetSetCount == 3)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try store.activeSessions.startSessionFromImport(plan, startedAt: startedAt)

        let snapshot = try store.activeSessions.fetchActiveSnapshot(at: startedAt)
        #expect(snapshot?.session.status == .active)
        #expect(snapshot?.session.source == .importSource)
        #expect(snapshot?.session.title == "PUSH")
        #expect(snapshot?.session.exercises.count == 1)
        #expect(snapshot?.session.exercises[0].sets.count == 3)
        #expect(snapshot?.session.exercises[0].sets.allSatisfy { $0.status == .planned } == true)
        #expect(snapshot?.session.exercises[0].sets[0].mass?.kilograms == 80)
        #expect(snapshot?.session.exercises[0].sets[0].rpe == 8)
    }
}
