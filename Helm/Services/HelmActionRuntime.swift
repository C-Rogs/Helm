import Core
import DesignSystem
import Foundation
import HealthKitIngest
import Persistence

@MainActor
enum HelmActionRuntime {
    enum AfterPersist {
        case coach
        case none
    }

    static var executor: HelmActionExecutor {
        HelmActionExecutor(
            manualMealService: NutritionBootstrap.manualMealService,
            persistence: PersistenceBootstrap.persistenceStore,
            mealRepeatService: NutritionBootstrap.mealRepeatService
        )
    }

    @discardableResult
    static func persist(
        _ command: HelmActionCommand,
        using executor: HelmActionExecutor,
        after: AfterPersist = .none
    ) async throws -> HelmActionResult {
        let result = try await executor.run(command)
        await apply(result, after: after)
        return result
    }

    @discardableResult
    static func perform(
        _ command: HelmActionCommand,
        after: AfterPersist
    ) async throws -> HelmActionResult {
        try await persist(command, using: executor, after: after)
    }

    static func apply(_ result: HelmActionResult, after: AfterPersist) async {
        if let day = result.nutritionDay {
            NutritionBootstrap.lastViewedHelmDay = day
        }
        for effect in result.sideEffects {
            switch effect {
            case let .refreshNutrition(day):
                NutritionBootstrap.refreshNutrition(for: day)
            case .refreshPrescription:
                await PlanBootstrap.refreshPrescriptionWithCalendar()
                await ProactiveBootstrap.refreshScheduling()
                NutritionBootstrap.refreshNutrition()
            }
        }
        if after == .coach {
            CoachApplyMomentStore.shared.play()
        }
    }

    static func startTodaysSession(
        controller: TrainSessionController,
        openTrainTab: Bool,
        useAdjustedPrescription: Bool = false
    ) async throws {
        try await WorkoutStartCoordinator.startTodaysSession(
            controller: controller,
            prescriptionService: PlanBootstrap.prescriptionService,
            openTrainTab: openTrainTab,
            useAdjustedPrescription: useAdjustedPrescription
        )
    }

    static func startImportedPlan(
        controller: TrainSessionController,
        plan: ImportedWorkoutPlan,
        openTrainTab: Bool
    ) async throws {
        try await WorkoutStartCoordinator.startImportedPlan(
            controller: controller,
            plan: plan,
            openTrainTab: openTrainTab
        )
    }

    static func startFromCoachPayload(
        _ payload: WorkoutStartPayload,
        helmDay: HelmDay,
        persistence: PersistenceStore
    ) async throws {
        try await CoachWorkoutStartAdjuster.start(
            payload: payload,
            helmDay: helmDay,
            persistence: persistence,
            prescriptionService: PlanBootstrap.prescriptionService
        ) { action in
            switch action {
            case let .prescription(useAdjusted):
                try await startTodaysSession(
                    controller: TrainBootstrap.sessionController,
                    openTrainTab: true,
                    useAdjustedPrescription: useAdjusted
                )
            case let .importedPlan(plan):
                try await startImportedPlan(
                    controller: TrainBootstrap.sessionController,
                    plan: plan,
                    openTrainTab: true
                )
            }
        }
    }
}
