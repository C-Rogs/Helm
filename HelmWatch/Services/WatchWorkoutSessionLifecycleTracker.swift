import Foundation
import os

@MainActor
final class WatchWorkoutSessionLifecycleTracker {
    private let log = OSLog(subsystem: "com.cameronro.helm", category: "Watch")
    private var signpostID: OSSignpostID?

    func begin(sessionID: String) {
        endIfNeeded()
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "WorkoutSessionLifecycle", signpostID: id)
        signpostID = id
        _ = sessionID
    }

    func markPauseResume() {
        guard let signpostID else { return }
        os_signpost(.event, log: log, name: "WorkoutSessionLifecycle", signpostID: signpostID)
    }

    func end() {
        endIfNeeded()
    }

    private func endIfNeeded() {
        guard let signpostID else { return }
        os_signpost(.end, log: log, name: "WorkoutSessionLifecycle", signpostID: signpostID)
        self.signpostID = nil
    }
}
