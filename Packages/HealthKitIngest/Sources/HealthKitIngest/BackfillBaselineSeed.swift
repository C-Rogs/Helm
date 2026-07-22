import Core
import Foundation
import Persistence
import ReadinessKit

/// Maps persisted health rows into readiness inputs and seeds EWMA baselines after backfill.
public enum BackfillBaselineSeed {
    public static func seedBaselines(
        from store: PersistenceStore,
        window: BackfillWindow,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> ReadinessBaselineState {
        let history = try readinessHistory(
            from: store,
            window: window,
            calendar: calendar,
            cutoff: cutoff
        )
        return ReadinessKit.seedBaselines(from: history)
    }

    public static func readinessHistory(
        from store: PersistenceStore,
        window: BackfillWindow,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [ReadinessDayInput] {
        try ReadinessHistoryBuilder.history(
            from: store,
            window: window,
            calendar: calendar,
            cutoff: cutoff
        )
    }
}
