import Foundation

/// Last-accepted watermark for one `WatchSyncPayload.Origin`.
public struct WatchSyncOriginWatermark: Equatable, Sendable {
    public var sequence: Int
    public var sentAt: TimeInterval

    public init(sequence: Int, sentAt: TimeInterval) {
        self.sequence = sequence
        self.sentAt = sentAt
    }
}

/// Per-origin stale/out-of-order guard for WatchConnectivity payloads.
///
/// Phone and Watch each own an independent sequence counter, so watermarks
/// must never be compared across origins.
public enum WatchSyncOrdering: Sendable {
    /// Whether `payload` should replace previously accepted state for its origin.
    public static func shouldAccept(
        sequence: Int,
        sentAt: TimeInterval,
        previous: WatchSyncOriginWatermark?
    ) -> Bool {
        guard let previous else { return true }
        if sequence > previous.sequence { return true }
        if sequence < previous.sequence { return false }
        return sentAt > previous.sentAt
    }

    public static func watermark(sequence: Int, sentAt: TimeInterval) -> WatchSyncOriginWatermark {
        WatchSyncOriginWatermark(sequence: sequence, sentAt: sentAt)
    }
}
