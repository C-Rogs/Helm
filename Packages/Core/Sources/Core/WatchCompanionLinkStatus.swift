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
        liveBPM: Int?
    ) -> WatchCompanionLinkStatus {
        if let liveBPM { return .live(bpm: liveBPM) }
        // Waiting chrome is Watch-only. Phone HKWorkoutSession still runs for
        // AirPods / BLE, but with no Watch app that is not a "waiting for HR" state.
        if canDriveWatch { return .connecting(.watch) }
        return .unavailable
    }
}
