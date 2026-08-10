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
                artist: "Artist A",
                bpm: 128
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(120),
                title: "Track B",
                artist: "Artist B",
                bpm: 140
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
        #expect(segments[0].bpm == 128)
        #expect(segments[1].startOffsetSeconds == 120)
        #expect(segments[1].endOffsetSeconds == 600)
        #expect(segments[1].title == "Track B")
        #expect(segments[1].bpm == 140)
    }

    @Test("drops non-positive BPM and keeps nil BPM tracks")
    func validatesBPM() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start,
                title: "Zero",
                artist: "A",
                bpm: 0
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(30),
                title: "Missing",
                artist: "B",
                bpm: nil
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(60),
                title: "Valid",
                artist: "C",
                bpm: 118
            )
        ]

        let segments = SessionMusicSegmentBuilder.build(
            samples: samples,
            startedAt: start,
            endedAt: start.addingTimeInterval(120)
        )

        #expect(segments.count == 3)
        #expect(segments[0].bpm == nil)
        #expect(segments[1].bpm == nil)
        #expect(segments[2].bpm == 118)
        #expect(segments[2].displayBPM == 118)
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
                artist: "Artist",
                bpm: 120
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(60),
                title: "Same",
                artist: "Artist",
                bpm: 120
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(180),
                title: "Other",
                artist: "Artist",
                bpm: 132
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
        #expect(segments[0].bpm == 120)
        #expect(segments[1].title == "Other")
        #expect(segments[1].bpm == 132)
    }

    @Test("merge keeps first available BPM")
    func mergeKeepsFirstBPM() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start,
                title: "Same",
                artist: "Artist",
                bpm: nil
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(60),
                title: "Same",
                artist: "Artist",
                bpm: 128
            )
        ]

        let segments = SessionMusicSegmentBuilder.build(
            samples: samples,
            startedAt: start,
            endedAt: start.addingTimeInterval(180)
        )

        #expect(segments.count == 1)
        #expect(segments[0].bpm == 128)
    }
}

@Suite("Session music genre summary")
struct SessionMusicGenreSummaryTests {
    @Test("carries genre through segment build and merge")
    func carriesGenre() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start,
                title: "Same",
                artist: "Artist",
                genre: "Hip-Hop"
            ),
            WorkoutMusicSample(
                sessionID: "s1",
                sampledAt: start.addingTimeInterval(60),
                title: "Same",
                artist: "Artist",
                genre: "Rap"
            )
        ]

        let segments = SessionMusicSegmentBuilder.build(
            samples: samples,
            startedAt: start,
            endedAt: start.addingTimeInterval(180)
        )

        #expect(segments.count == 1)
        #expect(segments[0].genre == "Hip-Hop")
    }

    @Test("orders genres by total duration and caps at limit")
    func ordersByDuration() {
        let segments = [
            SessionMusicSegment(startOffsetSeconds: 0, endOffsetSeconds: 60, genre: "Rock"),
            SessionMusicSegment(startOffsetSeconds: 60, endOffsetSeconds: 360, genre: "Hip-Hop"),
            SessionMusicSegment(startOffsetSeconds: 360, endOffsetSeconds: 540, genre: "Electronic"),
            SessionMusicSegment(startOffsetSeconds: 540, endOffsetSeconds: 600, genre: "Jazz")
        ]

        #expect(SessionMusicGenreSummary.format(segments: segments) == "Hip-Hop · Electronic · Rock")
        #expect(SessionMusicGenreSummary.format(segments: segments, limit: 1) == "Hip-Hop")
    }

    @Test("skips blank and unknown genres")
    func skipsBlanks() {
        let segments = [
            SessionMusicSegment(startOffsetSeconds: 0, endOffsetSeconds: 120, genre: "  "),
            SessionMusicSegment(startOffsetSeconds: 120, endOffsetSeconds: 240, genre: "Unknown"),
            SessionMusicSegment(startOffsetSeconds: 240, endOffsetSeconds: 300, genre: " Rock ")
        ]

        #expect(SessionMusicGenreSummary.format(segments: segments) == "Rock")
        #expect(SessionMusicGenreSummary.format(segments: []) == nil)
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
            maxLength: 18
        )
        #expect(truncated == "Romanian Deadlift…")
        #expect(truncated.count <= 18)
    }

    @Test("keeps leading whole words when shortening")
    func truncatesAtWordBoundary() {
        #expect(
            SessionExerciseMarkerBuilder.truncate(
                "Dumbbell Bench Press Incline",
                maxLength: 18
            ) == "Dumbbell Bench…"
        )
        #expect(
            SessionExerciseMarkerBuilder.truncate(
                "Extraordinarilylong Exercise",
                maxLength: 10
            ) == "Extraordi…"
        )
    }
}

@Suite("Spotify player state mapping")
struct SpotifyPlayerStateMappingTests {
    @Test("maps track fields into workout sample")
    func mapsTrackFields() {
        let sample = SpotifyPlayerStateMapping.workoutSample(
            sessionID: "session-1",
            title: "POWER",
            artist: "Kanye West",
            album: "My Beautiful Dark Twisted Fantasy"
        )

        #expect(sample?.title == "POWER")
        #expect(sample?.artist == "Kanye West")
        #expect(sample?.album == "My Beautiful Dark Twisted Fantasy")
        #expect(sample?.source == "spotify")
    }

    @Test("retains App Remote Spotify track ID")
    func retainsSpotifyTrackID() {
        let sample = SpotifyPlayerStateMapping.workoutSample(
            sessionID: "session-1",
            title: "Casio",
            artist: "Jungle",
            album: "For Ever",
            spotifyURI: "spotify:track:44ZKnfWEkp7wPs035j4Tua"
        )

        #expect(sample?.spotifyTrackID == "44ZKnfWEkp7wPs035j4Tua")
    }

    @Test("rejects non-track and malformed Spotify URIs")
    func rejectsInvalidSpotifyURIs() {
        #expect(SpotifyTrackIdentifier.fromURI("spotify:episode:44ZKnfWEkp7wPs035j4Tua") == nil)
        #expect(SpotifyTrackIdentifier.fromURI("spotify:track:not-a-track") == nil)
        #expect(SpotifyTrackIdentifier.fromURI(nil) == nil)
    }

    @Test("drops empty track metadata")
    func dropsEmptyMetadata() {
        #expect(SpotifyPlayerStateMapping.workoutSample(sessionID: "s", title: nil, artist: nil, album: nil) == nil)
        #expect(SpotifyPlayerStateMapping.workoutSample(sessionID: "s", title: "  ", artist: "", album: nil) == nil)
    }
}
