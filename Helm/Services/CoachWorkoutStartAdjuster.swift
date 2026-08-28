import CoachLLM
import Core
import Foundation
import HealthKitIngest
import Persistence

enum CoachWorkoutStartAction: Sendable {
    case prescription(useAdjusted: Bool)
    case importedPlan(ImportedWorkoutPlan)
}

enum CoachWorkoutStartAdjuster {
    enum StartError: LocalizedError, Equatable {
        case unsupportedSchema(String)
        case emptySession

        var errorDescription: String? {
            switch self {
            case let .unsupportedSchema(version):
                "Unsupported workout start format (\(version))."
            case .emptySession:
                "Coach proposal had no exercises to start."
            }
        }
    }

    @MainActor
    static func tryStartFromEmbeddedJSON(
        in text: String,
        helmDay: HelmDay,
        persistence: PersistenceStore,
        prescriptionService: PrescriptionService,
        onStart: @MainActor (CoachWorkoutStartAction) async throws -> Void
    ) async throws -> Bool {
        guard let payload = WorkoutStartPayloadParser.parse(from: text) else { return false }
        try await start(
            payload: payload,
            helmDay: helmDay,
            persistence: persistence,
            prescriptionService: prescriptionService,
            onStart: onStart
        )
        return true
    }

    @MainActor
    static func start(
        payload: WorkoutStartPayload,
        helmDay: HelmDay,
        persistence: PersistenceStore,
        prescriptionService: PrescriptionService,
        onStart: @MainActor (CoachWorkoutStartAction) async throws -> Void
    ) async throws {
        let supportedSchemas: Set<String> = [
            CoachOutputSchemaVersion.workoutStartV1.rawValue,
            CoachOutputSchemaVersion.workoutStartV2.rawValue
        ]
        guard supportedSchemas.contains(payload.schemaVersion) else {
            throw StartError.unsupportedSchema(payload.schemaVersion)
        }
        // helmDay on the payload is advisory. Confirm-to-start means start now;
        // do not block on coach off-by-one / cutoff drift (was a silent no-op before).

        if payload.hasDetailedSets {
            let plan = try WorkoutStartPlanBuilder.importedPlan(from: payload, persistence: persistence)
            guard !plan.exercises.isEmpty else { throw StartError.emptySession }
            try await onStart(.importedPlan(plan))
            return
        }

        let useAdjusted = payload.useAdjustedPrescription ?? false
        if let exercises = payload.exercises, !exercises.isEmpty {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let base = try await prescriptionService.todaysPrescription(readiness: readiness)
            // Rest days and custom lists must import named exercises, not start an empty engine session.
            if base.exercises.isEmpty {
                let plan = try WorkoutStartPlanBuilder.importedPlan(from: payload, persistence: persistence)
                guard !plan.exercises.isEmpty else { throw StartError.emptySession }
                try await onStart(.importedPlan(plan))
                return
            }
            if let adjusted = try WorkoutStartPrescriptionResolver.prescription(
                exerciseLabels: payload.exerciseLabels,
                base: base,
                persistence: persistence
            ) {
                let fingerprint = try PrescriptionHistoryBuilder.historyFingerprint(
                    from: persistence,
                    endingAt: helmDay
                )
                PrescriptionDayStore.save(adjusted, for: helmDay, historyFingerprint: fingerprint)
            } else if payload.schemaVersion == CoachOutputSchemaVersion.workoutStartV2.rawValue
                || payload.exercises != nil {
                let plan = try WorkoutStartPlanBuilder.importedPlan(from: payload, persistence: persistence)
                guard !plan.exercises.isEmpty else { throw StartError.emptySession }
                try await onStart(.importedPlan(plan))
                return
            }
        }

        // Bare payload with no exercises: only allowed for unchanged engine prescription.
        // Chat that discussed a custom list must not silently start a one-exercise stub.
        if payload.exercises == nil || payload.exercises?.isEmpty == true {
            if payload.schemaVersion == CoachOutputSchemaVersion.workoutStartV2.rawValue {
                throw StartError.emptySession
            }
            // v1 bare start of today's engine prescription remains valid.
            try await onStart(.prescription(useAdjusted: useAdjusted))
            return
        }

        try await onStart(.prescription(useAdjusted: useAdjusted || payload.exercises != nil))
    }
}
