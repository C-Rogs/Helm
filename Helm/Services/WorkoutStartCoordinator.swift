import Core
import Foundation
import HealthKitIngest

@MainActor
enum WorkoutStartCoordinator {
    enum StartError: LocalizedError {
        case alreadyActive
        case emptyPrescription

        var errorDescription: String? {
            switch self {
            case .alreadyActive:
                "A workout is already in progress."
            case .emptyPrescription:
                "No prescription available for today."
            }
        }
    }

    static func startTodaysSession(
        controller: TrainSessionController,
        prescriptionService: PrescriptionService,
        openTrainTab: Bool = false
    ) async throws {
        guard !controller.hasActiveSession else {
            throw StartError.alreadyActive
        }

        let readiness = ReadinessBootstrap.readinessService.state.score
        let prescription = try await prescriptionService.todaysPrescription(readiness: readiness)
        guard !prescription.exercises.isEmpty else {
            throw StartError.emptyPrescription
        }

        if openTrainTab {
            AppTabRouter.shared.openTrain()
        }

        await controller.startPrescription(prescription)
    }
}
