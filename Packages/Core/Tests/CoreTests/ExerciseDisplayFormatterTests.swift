import Core
import Testing

@Suite("Exercise display formatter")
struct ExerciseDisplayFormatterTests {
    @Test("prefers catalog display name")
    func prefersDisplayName() {
        let name = ExerciseDisplayFormatter.friendlyName(
            for: "seed-bench-press",
            displayNames: ["seed-bench-press": "Bench Press"]
        )
        #expect(name == "Bench Press")
    }

    @Test("humanizes seed prefix when display name missing")
    func humanizesSeedPrefix() {
        let name = ExerciseDisplayFormatter.friendlyName(for: "seed-bench-press")
        #expect(name == "Bench Press")
    }

    @Test("humanizes underscore IDs")
    func humanizesUnderscores() {
        let name = ExerciseDisplayFormatter.friendlyName(for: "incline_db_press")
        #expect(name == "Incline Db Press")
    }
}
