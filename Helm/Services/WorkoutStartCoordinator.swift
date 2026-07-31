import Core
import Foundation
import HealthKitIngest
import Persistence

@MainActor
enum WorkoutStartCoordinator {
    enum StartError: LocalizedError {
        case alreadyActive
        case emptyPrescription
        case startFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyActive:
                "A workout is already in progress."
            case .emptyPrescription:
                "No prescription available for today."
            case let .startFailed(message):
                message
            }
        }
    }

    static func startTodaysSession(
        controller: TrainSessionController,
        prescriptionService: PrescriptionService,
        openTrainTab: Bool = false,
        useAdjustedPrescription: Bool = false
    ) async throws {
        guard !controller.hasActiveSession else {
            throw StartError.alreadyActive
        }

        let readiness = ReadinessBootstrap.readinessService.state.score
        let prescription: SessionPrescription
        if useAdjustedPrescription,
           let adjusted = PrescriptionDayStore.load(for: HelmDay.day(for: .now, calendar: .current)),
           !adjusted.exercises.isEmpty {
            prescription = adjusted
        } else {
            prescription = try await prescriptionService.todaysPrescription(readiness: readiness)
        }
        guard !prescription.exercises.isEmpty else {
            throw StartError.emptyPrescription
        }

        if openTrainTab {
            AppTabRouter.shared.openTrain()
        }

        await controller.startPrescription(prescription)
        try ensureSessionStarted(controller)
    }

    static func startImportedPlan(
        controller: TrainSessionController,
        plan: ImportedWorkoutPlan,
        openTrainTab: Bool = false
    ) async throws {
        guard !controller.hasActiveSession else {
            throw StartError.alreadyActive
        }
        guard !plan.exercises.isEmpty else {
            throw StartError.emptyPrescription
        }

        if openTrainTab {
            AppTabRouter.shared.openTrain()
        }

        await controller.startWorkout(fromImportedPlan: plan, saveTemplate: false)
        try ensureSessionStarted(controller)
    }

    private static func ensureSessionStarted(_ controller: TrainSessionController) throws {
        guard controller.hasActiveSession else {
            throw StartError.startFailed(
                controller.errorMessage ?? "Could not start workout."
            )
        }
    }
}
