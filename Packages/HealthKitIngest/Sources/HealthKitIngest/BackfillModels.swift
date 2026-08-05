import Foundation

/// Historical fetch window for bounded HealthKit backfill.
public struct BackfillWindow: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case sixMonths
        case custom
    }

    public let start: Date
    public let end: Date
    public let kind: Kind

    public init(start: Date, end: Date, kind: Kind = .custom) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    /// Six calendar months ending at `end` (default: now).
    public static func sixMonths(
        endingAt end: Date = Date(),
        calendar: Calendar = .current
    ) -> BackfillWindow {
        let start = calendar.date(byAdding: .month, value: -6, to: end) ?? end
        return BackfillWindow(start: start, end: end, kind: .sixMonths)
    }

    /// Stable key for cursor lookup. Preset windows use a fixed id so completion survives relaunch.
    public var identityKey: String {
        switch kind {
        case .sixMonths:
            "sixMonths"
        case .custom:
            "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
        }
    }
}

public struct BackfillProgress: Sendable, Hashable {
    public let completedChunks: Int
    public let totalChunks: Int
    public let samplesIngestedThisRun: Int
    public let isComplete: Bool

    public init(
        completedChunks: Int,
        totalChunks: Int,
        samplesIngestedThisRun: Int,
        isComplete: Bool
    ) {
        self.completedChunks = completedChunks
        self.totalChunks = totalChunks
        self.samplesIngestedThisRun = samplesIngestedThisRun
        self.isComplete = isComplete
    }
}

public struct BackfillChunk: Sendable, Hashable {
    public let index: Int
    public let start: Date
    public let end: Date

    public init(index: Int, start: Date, end: Date) {
        self.index = index
        self.start = start
        self.end = end
    }
}

enum BackfillChunkPlanner {
    static let maximumSamplesPerQuery = 5_000

    static func monthlyChunks(in window: BackfillWindow, calendar: Calendar) -> [BackfillChunk] {
        var chunks: [BackfillChunk] = []
        var chunkStart = window.start
        var index = 0

        while chunkStart < window.end {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: chunkStart) else {
                break
            }
            let chunkEnd = min(nextMonth, window.end)
            chunks.append(BackfillChunk(index: index, start: chunkStart, end: chunkEnd))
            chunkStart = chunkEnd
            index += 1
        }

        return chunks
    }
}
