import Testing

@testable import Core

@Suite("Spotify reconnect backoff")
struct SpotifyReconnectBackoffTests {
    @Test("Live-session drop with attempts reset to 0 uses the first delay")
    func disconnectAfterSuccessUsesFirstSlot() {
        #expect(SpotifyReconnectBackoff.delayIndex(attempts: 0, delayCount: 3) == 0)
    }

    @Test("Failed connect attempts walk the delay ladder")
    func failedAttemptsWalkLadder() {
        #expect(SpotifyReconnectBackoff.delayIndex(attempts: 1, delayCount: 3) == 0)
        #expect(SpotifyReconnectBackoff.delayIndex(attempts: 2, delayCount: 3) == 1)
        #expect(SpotifyReconnectBackoff.delayIndex(attempts: 3, delayCount: 3) == 2)
    }

    @Test("Attempts past the ladder stay on the last delay")
    func clampsHigh() {
        #expect(SpotifyReconnectBackoff.delayIndex(attempts: 4, delayCount: 3) == 2)
        #expect(SpotifyReconnectBackoff.delayIndex(attempts: 100, delayCount: 3) == 2)
    }

    @Test("Empty delay list does not trap")
    func emptyListIsZero() {
        #expect(SpotifyReconnectBackoff.delayIndex(attempts: 0, delayCount: 0) == 0)
    }
}
