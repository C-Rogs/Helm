import Core
import Foundation
import HealthKitIngest
import Observation

@MainActor
@Observable
final class UsualMealStore {
    private(set) var proposalsByBucket: [MealBucket: UsualMealProposal] = [:]
    private(set) var loggingBucket: MealBucket?

    func reload(for day: HelmDay) {
        let resolver = UsualMealResolver(store: PersistenceBootstrap.persistenceStore)
        var next: [MealBucket: UsualMealProposal] = [:]
        for bucket in MealBucket.allCases {
            if let proposal = try? resolver.proposal(for: bucket, on: day) {
                next[bucket] = proposal
            }
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
