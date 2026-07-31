import Foundation
import Testing
@testable import Core

@Suite("Session heart rate buffer")
struct SessionHeartRateBufferTests {
    @Test("records samples and dedupes tight duplicates")
    func recordsAndDedupes() {
        var buffer = SessionHeartRateBuffer(minIntervalSeconds: 5)
        buffer.record(bpm: 120, offsetSeconds: 10)
        buffer.record(bpm: 120, offsetSeconds: 12)
        buffer.record(bpm: 125, offsetSeconds: 13)
        buffer.record(bpm: 130, offsetSeconds: 20)
        #expect(buffer.samples.map(\.bpm) == [120, 125, 130])
    }

    @Test("ignores non-positive bpm")
    func ignoresInvalid() {
        var buffer = SessionHeartRateBuffer()
        buffer.record(bpm: 0, offsetSeconds: 1)
        buffer.record(bpm: -3, offsetSeconds: 2)
        #expect(buffer.samples.isEmpty)
    }

    @Test("set markers from completed sets")
    func setMarkers() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSessionDraft(
            startedAt: start,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: "bench",
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 0,
                            status: .completed,
                            completedAt: start.addingTimeInterval(60)
                        ),
                        SetEntryDraft(
                            setIndex: 1,
                            status: .completed,
                            completedAt: start.addingTimeInterval(180)
                        ),
                        SetEntryDraft(setIndex: 2, status: .planned)
                    ]
                )
            ]
        )
        let markers = SessionSetMarkerBuilder.markers(from: session, startedAt: start)
        #expect(markers.map(\.offsetSeconds) == [60, 180])
        #expect(markers.map(\.setNumber) == [1, 2])
    }
}
