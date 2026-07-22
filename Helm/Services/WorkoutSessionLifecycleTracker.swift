import Diagnostics
import Foundation
import os

@MainActor
final class WorkoutSessionLifecycleTracker {
    private let signpost = HelmSignpost(name: .workoutSessionLifecycle, category: .logger)
    private var signpostID: OSSignpostID?
    private var sessionID: String?

    func begin(sessionID: String) {
        endIfNeeded()
        let id = signpost.makeSignpostID()
        signpost.begin(id: id)
        signpostID = id
        self.sessionID = sessionID
    }

    func markPauseResume() {
        guard let signpostID else { return }
        signpost.event(id: signpostID)
    }

    func end() {
        endIfNeeded()
        sessionID = nil
    }

    private func endIfNeeded() {
        guard let signpostID else { return }
        signpost.end(id: signpostID)
        self.signpostID = nil
    }
}
