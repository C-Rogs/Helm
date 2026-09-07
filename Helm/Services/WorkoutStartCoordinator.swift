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
                "No prescription available for that session."
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

    /// Starts a planned day's prescription as today's workout (does not rewrite the week calendar).
    static func startPlannedDaySession(
        day: HelmDay,
        controller: TrainSessionController,
        prescriptionService: PrescriptionService,
        openTrainTab: Bool = false
    ) async throws {
        guard !controller.hasActiveSession else {
            throw StartError.alreadyActive
        }

        let readiness = ReadinessBootstrap.readinessService.state.score
        let planned = try await prescriptionService.prescription(for: day, readiness: readiness)
        guard !planned.exercises.isEmpty else {
            throw StartError.emptyPrescription
        }

        let today = HelmDay.day(for: .now, calendar: .current)
        let prescription = SessionPrescription(
            id: planned.id,
            helmDay: today,
            title: planned.title,
            exercises: planned.exercises
        )

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
