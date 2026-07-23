import Foundation
import os

@MainActor
final class LiveWorkoutBuilderTeardownTracker {
    private let log = OSLog(subsystem: "com.cameronro.helm", category: "Watch")
    private var signpostID: OSSignpostID?

    func begin(sessionID: String) {
        endIfNeeded()
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "LiveWorkoutBuilderTeardown", signpostID: id)
        signpostID = id
        _ = sessionID
    }

    func end() {
        endIfNeeded()
    }

    private func endIfNeeded() {
        guard let signpostID else { return }
        os_signpost(.end, log: log, name: "LiveWorkoutBuilderTeardown", signpostID: signpostID)
        self.signpostID = nil
    }
}
