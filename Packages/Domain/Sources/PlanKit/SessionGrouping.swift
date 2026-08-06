import Core
import Foundation

enum SessionGrouping {
    /// Gap between consecutive sets beyond which a new training session begins.
    static let sessionRestGap: TimeInterval = 4 * 60 * 60

    static func groupIntoSessions(_ sets: [LoggedSet]) -> [[LoggedSet]] {
        guard !sets.isEmpty else { return [] }
        let sorted = sets.sorted { $0.completedAt < $1.completedAt }
        var sessions: [[LoggedSet]] = []
        var current: [LoggedSet] = [sorted[0]]
        for set in sorted.dropFirst() {
            let gap = set.completedAt.timeIntervalSince(current.last!.completedAt)
            if gap <= sessionRestGap {
                current.append(set)
            } else {
                sessions.append(current)
                current = [set]
            }
        }
        sessions.append(current)
        return sessions
    }
}
