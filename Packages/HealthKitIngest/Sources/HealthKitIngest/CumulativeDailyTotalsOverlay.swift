import Core
import Foundation
import HealthKit

/// Replaces delta-summed cumulative metrics with HealthKit day totals.
struct CumulativeDailyTotalsOverlay: Sendable {
    private let store: any HealthKitStoreClient
    private let writer: IngestPersistenceWriter
    private let calendar: Calendar
    private let cutoff: DayCutoff

    init(
        store: any HealthKitStoreClient,
        writer: IngestPersistenceWriter,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.writer = writer
        self.calendar = calendar
        self.cutoff = cutoff
    }

    func refresh(kind: HealthKitSampleKind, extraDays: Set<HelmDay>) async throws {
        guard kind.isCumulativeDailyTotal else { return }

        var days = extraDays
        days.insert(HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar))

        for day in days {
            guard let start = day.startInstant(cutoff: cutoff, calendar: calendar),
                  let end = day.endInstant(cutoff: cutoff, calendar: calendar)
            else { continue }
            let queryEnd = min(end, Date())
            guard queryEnd > start else { continue }

            switch kind {
            case .stepCount:
                if let sum = await store.fetchCumulativeSum(
                    identifier: .stepCount,
                    unit: .count(),
                    start: start,
                    end: queryEnd
                ) {
                    try writer.applyAuthoritativeCumulative(
                        helmDay: day,
                        stepCount: Int(sum.rounded())
                    )
                }
            case .activeEnergy:
                if let kcal = await store.fetchCumulativeSum(
                    identifier: .activeEnergyBurned,
                    unit: .kilocalorie(),
                    start: start,
                    end: queryEnd
                ) {
                    try writer.applyAuthoritativeCumulative(
                        helmDay: day,
                        activeEnergy: Energy(kilocalories: kcal)
                    )
                }
            case .basalEnergy:
                if let kcal = await store.fetchCumulativeSum(
                    identifier: .basalEnergyBurned,
                    unit: .kilocalorie(),
                    start: start,
                    end: queryEnd
                ) {
                    try writer.applyAuthoritativeCumulative(
                        helmDay: day,
                        restingEnergyKcal: kcal
                    )
                }
            default:
                break
            }
        }
    }
}
