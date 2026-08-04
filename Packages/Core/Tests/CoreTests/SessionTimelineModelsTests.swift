import Foundation
import Testing
@testable import Core

@Suite("Session music segments")
struct SessionMusicSegmentBuilderTests {
    @Test("builds spans until next sample or session end")
    func buildsSpans() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(600)
        let samples = [
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(0),
                title: "Track A",
                artist: "Artist A"
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(120),
                title: "Track B",
                artist: "Artist B"
            )
        ]

        let segments = SessionMusicSegmentBuilder.build(
            samples: samples,
            startedAt: start,
            endedAt: end
        )

        #expect(segments.count == 2)
        #expect(segments[0].startOffsetSeconds == 0)
        #expect(segments[0].endOffsetSeconds == 120)
        #expect(segments[0].title == "Track A")
        #expect(segments[1].startOffsetSeconds == 120)
        #expect(segments[1].endOffsetSeconds == 600)
        #expect(segments[1].title == "Track B")
    }

    @Test("drops empty title and artist samples")
    func dropsEmpty() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            WorkoutMusicSample(sessionID: "s1", sampledAt: start, title: nil, artist: nil),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(30),
                title: "Only Title",
                artist: nil
            )
        ]

        let segments = SessionMusicSegmentBuilder.build(
            samples: samples,
            startedAt: start,
            endedAt: start.addingTimeInterval(120)
        )

        #expect(segments.count == 1)
        #expect(segments[0].title == "Only Title")
    }

    @Test("merges adjacent identical tracks")
    func mergesAdjacent() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start,
                title: "Same",
                artist: "Artist"
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(60),
                title: "Same",
                artist: "Artist"
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(180),
                title: "Other",
                artist: "Artist"
            )
        ]

        let segments = SessionMusicSegmentBuilder.build(
            samples: samples,
            startedAt: start,
            endedAt: start.addingTimeInterval(300)
        )

        #expect(segments.count == 2)
        #expect(segments[0].startOffsetSeconds == 0)
        #expect(segments[0].endOffsetSeconds == 180)
        #expect(segments[1].title == "Other")
    }
}

@Suite("Session exercise markers")
struct SessionExerciseMarkerBuilderTests {
    @Test("marks first completed set per exercise")
    func exerciseTransitions() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSessionDraft(
            startedAt: start,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: "seed-bench-press",
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
                            completedAt: start.addingTimeInterval(120)
                        )
                    ]
                ),
                WorkoutSessionExerciseDraft(
                    exerciseID: "seed-squat",
                    displayOrder: 1,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 0,
                            status: .completed,
                            completedAt: start.addingTimeInterval(240)
                        )
                    ]
                )
            ]
        )

        let markers = SessionExerciseMarkerBuilder.markers(
            from: session,
            startedAt: start,
            displayNames: [
                "seed-bench-press": "Bench Press",
                "seed-squat": "Squat (Barbell)"
            ]
        )

        #expect(markers.count == 2)
        #expect(markers[0].offsetSeconds == 60)
        #expect(markers[0].shortName == "Bench Press")
        #expect(markers[1].offsetSeconds == 240)
        #expect(markers[1].shortName == "Squat (Barbell)")
    }

    @Test("truncates long exercise names")
    func truncatesNames() {
        let truncated = SessionExerciseMarkerBuilder.truncate(
            "Romanian Deadlift With Long Descriptor",
            maxLength: 16
        )
        #expect(truncated == "Romanian Deadli…")
        #expect(truncated.count <= 16)
    }
}
