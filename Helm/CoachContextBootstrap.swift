import CoachLLM
import Core
import Foundation
import HealthKitIngest
import Persistence

enum CoachContextBootstrap {
    @MainActor
    static func assemble(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        lookbackDays: Int = CoachContextAssembler.defaultLookbackDays
    ) async throws -> CoachContextDays {
        let weekEnd = endDay.adding(days: WeekAheadScheduleBuilder.horizonDays - 1)
        let busyDayHints = await CalendarHintBootstrap.service.busyDayHints(
            from: endDay,
            through: weekEnd
        )
        return try await CoachContextAssembler.assemble(
            from: store,
            endingAt: endDay,
            lookbackDays: lookbackDays,
            busyDayHints: busyDayHints
        )
    }
}
