import Core
import DesignSystem
import Foundation
import HealthKitIngest
import Persistence

enum UsualMealIntentBootstrap {
    @MainActor
    static func log(bucket: MealBucket, helmDay: HelmDay? = nil) async -> UsualMealLogOutcome {
        let calendar = Calendar.current
        let now = Date()
        let day = helmDay ?? HelmDay.day(for: now, calendar: calendar)
        let store = PersistenceBootstrap.persistenceStore

        do {
            let existing = try store.nutrition.fetchMeals(for: day).filter { $0.bucket == bucket }
            if !existing.isEmpty {
                return .alreadyLogged(bucket)
            }

            let resolver = UsualMealResolver(store: store, calendar: calendar)
            guard let proposal = try resolver.proposal(for: bucket, on: day) else {
                return .noUsual(bucket)
            }

            let today = HelmDay.day(for: now, calendar: calendar)
            let loggedAt = MealLogInstant.loggedAt(
                for: day,
                bucket: bucket,
                today: today,
                calendar: calendar
            )
            _ = try await HelmActionRuntime.persist(
                .logUsual(bucket: bucket, helmDay: day, loggedAt: loggedAt, proposal: proposal),
                using: HelmActionRuntime.executor
            )
            UsualMealPreferences.clearSkip(day: day, bucket: bucket)
            HapticEngine.shared.play(.mealConfirmed)
            return .logged(displayName: proposal.displayName, bucket: bucket, helmDay: day)
        } catch UsualMealLogError.alreadyLogged {
            return .alreadyLogged(bucket)
        } catch UsualMealLogError.noUsual {
            return .noUsual(bucket)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
