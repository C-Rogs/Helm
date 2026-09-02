/// Delay-slot math for Spotify App Remote reconnect.
///
/// A successful connect resets the attempt counter to 0. A later drop must
/// still pick a delay without indexing `-1`.
public enum SpotifyReconnectBackoff {
    public static func delayIndex(attempts: Int, delayCount: Int) -> Int {
        guard delayCount > 0 else { return 0 }
        return min(max(attempts - 1, 0), delayCount - 1)
    }
}
