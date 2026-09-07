import Testing
@testable import DesignSystem

@Suite("Exercise history snapshots")
struct ExerciseHistorySnapshotTests {
    @Test("bench fixture snapshot")
    func benchSnapshot() {
        let text = ExerciseHistorySnapshot.text(for: .benchFixture)

        #expect(text == benchSnapshotText)
        #expect(text.contains("Bench Press (Barbell)"))
        #expect(text.contains("PREV=80×8"))
        #expect(text.contains("e1RM=102.5"))
        #expect(text.contains("Brace hard and pull shoulder blades together."))
    }

    @Test("cold start fixture snapshot")
    func coldStartSnapshot() {
        let text = ExerciseHistorySnapshot.text(for: .coldStartFixture)

        #expect(text == coldStartSnapshotText)
        #expect(text.contains("## Current e1RM"))
        #expect(text.contains("PREV=nil"))
        #expect(text.contains("e1RM history"))
        #expect(text.contains("- none"))
        #expect(text.contains("cues=none"))
    }

    @Test("snapshot text is byte-stable across calls")
    func snapshotByteStable() {
        let first = ExerciseHistorySnapshot.text(for: .benchFixture)
        let second = ExerciseHistorySnapshot.text(for: .benchFixture)

        #expect(first == second)
        #expect(first.utf8.elementsEqual(second.utf8))
    }
}

private let benchSnapshotText = """
# Exercise detail
## Exercise
Bench Press (Barbell)
## Form
image=https://example.com/bench.gif
instruction=Lie on a flat bench, plant feet, and press the bar from mid-chest to lockout.
- cue 1: Brace hard and pull shoulder blades together.
- cue 2: Drive through your heels and keep your chest proud.
- cue 3: Press up and slightly back.
## Current e1RM
102.5
## PREV
- set 1 (W): PREV=60×10 | session=Jul 18
- set 2 (1): PREV=80×8 | session=Jul 18
- set 3 (1): PREV=80×8 | session=Jul 18
## e1RM history
- Jul 18: e1RM=102.5
- Jul 3: e1RM=98.0
- Jun 12: e1RM=95.0
"""

private let coldStartSnapshotText = """
# Exercise detail
## Exercise
Lat Pulldown (Cable)
## Form
image=nil
instruction=nil
cues=none
## Current e1RM
nil
## PREV
- set 1 (1): PREV=nil | session=nil
## e1RM history
- none
"""
