import Core
import Foundation
import Testing

@Suite("StandingConstraintNotes")
struct StandingConstraintNotesTests {
    private let notedOn = HelmDay(year: 2026, month: 8, day: 5)
    private let until = HelmDay(year: 2026, month: 8, day: 8)

    @Test("formats add line with until and joint")
    func formatsAddLine() {
        let line = StandingConstraintNotes.formatAddLine(
            note: "Soft pause overhead pressing",
            joint: "shoulder",
            notedOn: notedOn,
            until: until
        )
        #expect(line == "2026-08-05 [until:2026-08-08] [joint:shoulder] Soft pause overhead pressing")
    }

    @Test("active shoulder pauses vertical press and nudges warm-up")
    func activeShoulder() {
        let text = StandingConstraintNotes.formatAddLine(
            note: "Shoulder niggle",
            joint: "shoulder",
            notedOn: notedOn,
            until: until
        )
        let mid = StandingConstraintNotes.evaluate(text, on: HelmDay(year: 2026, month: 8, day: 7))
        #expect(mid.pauseVerticalPress)
        #expect(mid.encourageWarmUpStretch)
        #expect(mid.rationaleNotes.contains(where: { $0.contains("soft pause overhead") }))
    }

    @Test("day after until restores overhead pressing")
    func expiredRestoresOHP() {
        let text = StandingConstraintNotes.formatAddLine(
            note: "Shoulder niggle",
            joint: "shoulder",
            notedOn: notedOn,
            until: until
        )
        let after = StandingConstraintNotes.evaluate(text, on: HelmDay(year: 2026, month: 8, day: 9))
        #expect(!after.pauseVerticalPress)
        #expect(after.encourageWarmUpStretch)
        #expect(after.rationaleNotes.contains(where: { $0.contains("allowed again") }))
    }

    @Test("clear marks resolved and stops signals")
    func clearStopsSignals() {
        let added = StandingConstraintNotes.append(
            note: "Shoulder niggle",
            joint: "shoulder",
            notedOn: notedOn,
            until: until,
            to: ""
        )
        let cleared = StandingConstraintNotes.clear(
            joint: "shoulder",
            on: HelmDay(year: 2026, month: 8, day: 6),
            in: added
        )
        #expect(cleared.contains("[resolved:2026-08-06]"))
        let eval = StandingConstraintNotes.evaluate(cleared, on: HelmDay(year: 2026, month: 8, day: 6))
        #expect(!eval.pauseVerticalPress)
        #expect(!eval.encourageWarmUpStretch)
    }

    @Test("legacy dated line without until uses +3 day window")
    func legacyWindow() {
        let text = "2026-08-05: No overhead pressing (shoulder)."
        let active = StandingConstraintNotes.evaluate(text, on: HelmDay(year: 2026, month: 8, day: 7))
        #expect(active.pauseVerticalPress)
        let expired = StandingConstraintNotes.evaluate(text, on: HelmDay(year: 2026, month: 8, day: 9))
        #expect(!expired.pauseVerticalPress)
    }
}
