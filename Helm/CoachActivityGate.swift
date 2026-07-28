import Foundation
import Observation

@MainActor
@Observable
final class CoachActivityGate {
    static let shared = CoachActivityGate()

    enum Surface: String, Sendable {
        case chat
        case inSession
    }

    private(set) var activeSurface: Surface?

    var allowsParallelCoaches = true

    private init() {}

    func begin(_ surface: Surface) {
        if allowsParallelCoaches {
            activeSurface = surface
            return
        }
        guard activeSurface == nil || activeSurface == surface else { return }
        activeSurface = surface
    }

    func end(_ surface: Surface) {
        guard activeSurface == surface else { return }
        activeSurface = nil
    }

    func isBlocked(for surface: Surface) -> Bool {
        guard !allowsParallelCoaches else { return false }
        guard let activeSurface else { return false }
        return activeSurface != surface
    }

    func blockingMessage(for surface: Surface) -> String? {
        guard isBlocked(for: surface) else { return nil }
        switch activeSurface {
        case .chat:
            return "Coach is responding in Chat. Wait or cancel that turn first."
        case .inSession:
            return "Coach is responding in your workout. Wait or cancel that turn first."
        case .none:
            return nil
        }
    }
}
