import Core
import Foundation
import HealthKitIngest
import Persistence
import UIKit

enum ProactiveBootstrap {
    private static let persistence = PersistenceBootstrap.persistenceStore

    @MainActor
    static let notificationScheduler = ProactiveNotificationScheduler(persistence: persistence)

    @MainActor
    static let thresholdInsightService = ThresholdInsightService(persistence: persistence)

    @MainActor
    static func start() {
        PatternBackgroundScheduler.schedule()
        Task {
            await refreshScheduling()
            await refreshThresholdInsights()
            await refreshPatterns()
        }
    }

    @MainActor
    static func refreshScheduling() async {
        if FestivalModePreferences.shared.isFestivalModeEnabled {
            await NutritionBootstrap.usualMealScheduler.cancelAll()
            return
        }
        let readiness = ReadinessBootstrap.readinessService.state.score?.score
        let summary = PlanBootstrap.prescriptionService.state.summary
        await notificationScheduler.schedulePreWorkoutPrimeIfNeeded(
            summary: summary,
            readinessScore: readiness
        )
        await rescheduleUsualMeals()
    }

    @MainActor
    static func rescheduleUsualMeals() async {
        guard !FestivalModePreferences.shared.isFestivalModeEnabled else { return }
        await NutritionBootstrap.usualMealScheduler.reschedule()
    }

    /// Drop today's usual-meal nudges immediately, then rebuild in the background.
    @MainActor
    static func noteNutritionLogged(day: HelmDay) async {
        await NutritionBootstrap.usualMealScheduler.cancelPending(for: day)
        Task(priority: .utility) { @MainActor in
            await rescheduleUsualMeals()
        }
    }

    @MainActor
    static func cancelAllScheduled() async {
        await notificationScheduler.cancelAllScheduled()
        await NutritionBootstrap.usualMealScheduler.cancelAll()
    }

    @MainActor
    static func refreshThresholdInsights() async {
        await thresholdInsightService.refresh(today: ReadinessBootstrap.readinessService.state.score)
    }

    @MainActor
    static func refreshPatterns() async {
        let service = PatternEvaluationService(store: persistence)
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        #else
        let charging = false
        #endif
        await service.refresh(isCharging: charging)
    }
}
