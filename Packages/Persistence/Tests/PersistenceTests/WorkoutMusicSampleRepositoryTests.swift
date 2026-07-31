import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Workout music samples")
struct WorkoutMusicSampleRepositoryTests {
    @Test("inserts stubbed now-playing sample")
    func insertStubbedSample() throws {
        let store = try PersistenceStore.inMemory()
        let sample = WorkoutMusicSample(
            sessionID: "session-music-1",
            sampledAt: Date(timeIntervalSince1970: 1_700_000_100),
            title: "Iron",
            artist: "Woodkid",
            album: "The Golden Age",
            genre: "Electronic",
            bpm: 128,
            playbackRate: 1,
            source: "nowPlaying"
        )
        try store.workoutMusicSamples.insert(sample)
        let loaded = try store.workoutMusicSamples.list(sessionID: "session-music-1")
        #expect(loaded.count == 1)
        #expect(loaded[0].title == "Iron")
        #expect(loaded[0].artist == "Woodkid")
        #expect(loaded[0].bpm == 128)
        #expect(loaded[0].genre == "Electronic")
    }
}
