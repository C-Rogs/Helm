import Core
import Foundation
import HealthKitIngest
import Observation
import Persistence

@MainActor
@Observable
final class UsualMealStore {
    private(set) var proposalsByBucket: [MealBucket: UsualMealProposal] = [:]
    private(set) var loggingBucket: MealBucket?
    private let persistence: PersistenceStore
    private let now: @Sendable () -> Date

    init(
        persistence: PersistenceStore = PersistenceBootstrap.persistenceStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.now = now
    }

    func reload(for day: HelmDay) {
        let calendar = Calendar.current
        let currentDate = now()
        let resolver = UsualMealResolver(store: persistence, calendar: calendar)
        let isToday = day == HelmDay.day(for: currentDate, calendar: calendar)
        var next: [MealBucket: UsualMealProposal] = [:]
        for bucket in MealBucket.allCases {
            guard let proposal = try? resolver.proposal(for: bucket, on: day) else { continue }
            guard !isToday || !UsualMealPreferences.isNudgeCoolingDown(bucket: bucket, now: currentDate) else {
                continue
            }
            next[bucket] = proposal
        }
        proposalsByBucket = next
    }

    func proposal(for bucket: MealBucket) -> UsualMealProposal? {
        proposalsByBucket[bucket]
    }

    var nextDashboardProposal: UsualMealProposal? {
        for bucket in [MealBucket.breakfast, .lunch, .dinner] {
            if let proposal = proposalsByBucket[bucket] {
                return proposal
            }
        }
        return nil
    }

    func log(_ proposal: UsualMealProposal, helmDay: HelmDay) async {
        loggingBucket = proposal.bucket
        defer { loggingBucket = nil }
        _ = await UsualMealIntentBootstrap.log(bucket: proposal.bucket, helmDay: helmDay)
        reload(for: helmDay)
    }
}
