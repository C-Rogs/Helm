import Foundation
import Testing
@testable import Core

@Suite("Song tempo query")
struct SongTempoQueryTests {
    @Test("requires a title")
    func requiresTitle() {
        #expect(SongTempoQuery(title: nil, artist: "Eminem") == nil)
        #expect(SongTempoQuery(title: "   ", artist: "Eminem") == nil)
        #expect(SongTempoQuery(title: "Lose Yourself", artist: nil) != nil)
    }

    @Test("search term leads with artist for catalog free-text search")
    func searchTerm() {
        let withArtist = SongTempoQuery(title: "Lose Yourself", artist: "Eminem")
        #expect(withArtist?.searchTerm == "Eminem Lose Yourself")

        let titleOnly = SongTempoQuery(title: "Lose Yourself", artist: "  ")
        #expect(titleOnly?.searchTerm == "Lose Yourself")
        #expect(titleOnly?.artist == nil)
    }

    @Test("cache key folds edits, case, and punctuation together")
    func cacheKeyFolds() {
        let plain = SongTempoQuery(title: "POWER", artist: "Kanye West")
        let noisy = SongTempoQuery(title: "power (Radio Edit)", artist: "Kanye  West")
        #expect(plain?.cacheKey == noisy?.cacheKey)

        let other = SongTempoQuery(title: "Stronger", artist: "Kanye West")
        #expect(plain?.cacheKey != other?.cacheKey)
    }
}

@Suite("Song tempo matching")
struct SongTempoMatchingTests {
    @Test("rejects tempo outside plausible music range")
    func validatesRange() {
        #expect(SongTempoMatching.validated(128) == 128)
        #expect(SongTempoMatching.validated(0) == nil)
        #expect(SongTempoMatching.validated(39) == nil)
        #expect(SongTempoMatching.validated(221) == nil)
        #expect(SongTempoMatching.validated(nil) == nil)
        #expect(SongTempoMatching.validated(.infinity) == nil)
    }

    @Test("doubles half-time DnB but preserves other low tempos")
    func normalisesDrumAndBassTempo() {
        #expect(SongTempoMatching.workoutTempo(87, genre: "Drum & Bass") == 174)
        #expect(SongTempoMatching.workoutTempo(87, genre: "Drum and Bass") == 174)
        #expect(SongTempoMatching.workoutTempo(87, genre: "Hip-Hop") == 87)
        #expect(SongTempoMatching.workoutTempo(120, genre: "Drum & Bass") == 120)
        #expect(SongTempoMatching.workoutTempo(87, genre: nil) == 87)
    }

    @Test("normalisation strips diacritics, brackets, and version suffixes")
    func normalises() {
        #expect(SongTempoMatching.normalized("Björk") == "bjork")
        #expect(SongTempoMatching.normalized("Glue (Extended Mix)") == "glue")
        #expect(SongTempoMatching.normalized("Enter Sandman - Remastered 2021") == "enter sandman")
        #expect(SongTempoMatching.normalized("Fred again..") == "fred again")
        #expect(SongTempoMatching.normalized("HUMBLE.") == "humble")
    }

    @Test("keeps hyphenated titles that are not version suffixes")
    func keepsMeaningfulHyphens() {
        #expect(SongTempoMatching.normalized("Marvins Room - Bonus") == "marvins room")
        #expect(SongTempoMatching.normalized("Ready - Set - Go") == "ready set go")
    }

    @Test("accepts the same recording across edit labels")
    func acceptsSameRecording() {
        let query = SongTempoQuery(title: "Get Lucky", artist: "Daft Punk")!
        #expect(
            SongTempoMatching.matches(
                candidateTitle: "Get Lucky (Radio Edit)",
                candidateArtist: "Daft Punk",
                query: query
            )
        )
    }

    @Test("rejects a different artist's track with the same title")
    func rejectsOtherArtist() {
        let query = SongTempoQuery(title: "Rumble", artist: "Fred again..")!
        #expect(
            SongTempoMatching.matches(
                candidateTitle: "Rumble",
                candidateArtist: "Skrillex",
                query: query
            ) == false
        )
    }

    @Test("rejects a different title from the same artist")
    func rejectsOtherTitle() {
        let query = SongTempoQuery(title: "POWER", artist: "Kanye West")!
        #expect(
            SongTempoMatching.matches(
                candidateTitle: "Stronger",
                candidateArtist: "Kanye West",
                query: query
            ) == false
        )
    }

    @Test("matches on title alone when the source reported no artist")
    func matchesTitleOnly() {
        let query = SongTempoQuery(title: "Breathe", artist: nil)!
        #expect(
            SongTempoMatching.matches(
                candidateTitle: "Breathe",
                candidateArtist: "The Prodigy",
                query: query
            )
        )
    }
}

@Suite("Session music segment tempo filler")
struct SessionMusicSegmentTempoFillerTests {
    private func segments() -> [SessionMusicSegment] {
        [
            SessionMusicSegment(
                startOffsetSeconds: 0,
                endOffsetSeconds: 100,
                title: "Captured",
                artist: "Artist A",
                bpm: 120
            ),
            SessionMusicSegment(
                startOffsetSeconds: 100,
                endOffsetSeconds: 200,
                title: "Needs Tempo",
                artist: "Artist B"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 200,
                endOffsetSeconds: 300,
                title: "Needs Tempo (Live)",
                artist: "Artist B"
            ),
            SessionMusicSegment(startOffsetSeconds: 300, endOffsetSeconds: 400)
        ]
    }

    @Test("collects one query per distinct untagged track")
    func collectsDistinctQueries() {
        let queries = SessionMusicSegmentTempoFiller.missingTempoQueries(in: segments())
        #expect(queries.count == 1)
        #expect(queries.first?.title == "Needs Tempo")
        #expect(queries.first?.artist == "Artist B")
    }

    @Test("fills untagged segments and leaves captured tempo alone")
    func fillsMissing() {
        let query = SongTempoQuery(title: "Needs Tempo", artist: "Artist B")!
        let filled = SessionMusicSegmentTempoFiller.apply(
            tempos: [query.cacheKey: 174],
            to: segments()
        )

        #expect(filled[0].bpm == 120)
        #expect(filled[1].bpm == 174)
        #expect(filled[2].bpm == 174)
        #expect(filled[3].bpm == nil)
    }

    @Test("ignores implausible resolved tempo")
    func ignoresBadTempo() {
        let query = SongTempoQuery(title: "Needs Tempo", artist: "Artist B")!
        let filled = SessionMusicSegmentTempoFiller.apply(
            tempos: [query.cacheKey: 0],
            to: segments()
        )
        #expect(filled[1].bpm == nil)
    }

    @Test("returns segments unchanged when nothing resolved")
    func noopWhenEmpty() {
        let original = segments()
        #expect(SessionMusicSegmentTempoFiller.apply(tempos: [:], to: original) == original)
    }
}
