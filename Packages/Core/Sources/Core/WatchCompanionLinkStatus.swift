import Foundation

/// Hint while waiting for the first live BPM sample.
public enum WaitingForHeartRateSource: Equatable, Sendable {
    case watch
    case phone
}

/// Phone Train header chrome for live HR.
public enum WatchCompanionLinkStatus: Equatable, Sendable {
    /// No live HR session active yet; hide HR chrome.
    case unavailable
    /// Waiting for first BPM (Watch and/or phone external sensors).
    case connecting(WaitingForHeartRateSource)
    /// Fresh live BPM from any source.
    case live(bpm: Int)

    public static func resolve(
        canDriveWatch: Bool,
        phoneHRActive: Bool = false,
        liveBPM: Int?
    ) -> WatchCompanionLinkStatus {
        if let liveBPM { return .live(bpm: liveBPM) }
        // Prefer Watch raise-wrist copy when companion expected; else phone sensors.
        if canDriveWatch { return .connecting(.watch) }
        if phoneHRActive { return .connecting(.phone) }
        return .unavailable
    }
}
