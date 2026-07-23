import Core
import Testing

@Suite("MethodologyPreferences")
struct MethodologyPreferencesTests {
    @Test("parse and merge round-trip structured keys")
    func roundTrip() {
        let source = """
        Prefer short weekday sessions.
        equipment=barbell,dumbbell
        selectionBias=stretch
        """

        let parsed = MethodologyPreferences.parse(from: source)
        #expect(parsed.freeform == "Prefer short weekday sessions.")
        #expect(parsed.preferences.allowedEquipment == ["barbell", "dumbbell"])
        #expect(parsed.preferences.selectionBias == .stretch)

        let merged = parsed.preferences.merge(into: source)
        let again = MethodologyPreferences.parse(from: merged)
        #expect(again.freeform == "Prefer short weekday sessions.")
        #expect(again.preferences == parsed.preferences)
    }

    @Test("empty equipment means no filter")
    func emptyEquipmentFilter() {
        let prefs = MethodologyPreferences()
        #expect(prefs.availableEquipmentFilter == nil)
    }
}
