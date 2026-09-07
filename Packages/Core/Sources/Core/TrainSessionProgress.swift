import Foundation

public struct TrainSessionProgress: Sendable, Hashable, Equatable {
    public let elapsedSeconds: Int
    public let completedSetCount: Int
    public let totalSetCount: Int

    public init(elapsedSeconds: Int, completedSetCount: Int, totalSetCount: Int) {
        self.elapsedSeconds = elapsedSeconds
        self.completedSetCount = completedSetCount
        self.totalSetCount = totalSetCount
    }

    public static func from(snapshot: ActiveSessionSnapshot, now: Date = Date()) -> TrainSessionProgress {
        let elapsed = max(0, Int(now.timeIntervalSince(snapshot.session.startedAt)))
        let workingSets = snapshot.session.exercises.flatMap(\.sets).filter { !$0.setType.isWarmup }
        let completed = workingSets.filter { $0.status == .completed }.count
        return TrainSessionProgress(
            elapsedSeconds: elapsed,
            completedSetCount: completed,
            totalSetCount: workingSets.count
        )
    }
}

public enum TrainSessionProgressFormatter {
    public static func elapsedLabel(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    public static func setCountLabel(completed: Int, total: Int) -> String {
        "\(completed)/\(total) sets"
    }
}
