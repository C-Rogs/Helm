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
    @MainActor
    static func tryStartFromEmbeddedJSON(
        in text: String,
        helmDay: HelmDay,
        persistence: PersistenceStore,
        prescriptionService: PrescriptionService,
        onStart: @MainActor (CoachWorkoutStartAction) async throws -> Void
    ) async throws -> Bool {
        guard let payload = WorkoutStartPayloadParser.parse(from: text) else { return false }
        let supportedSchemas: Set<String> = [
            CoachOutputSchemaVersion.workoutStartV1.rawValue,
            CoachOutputSchemaVersion.workoutStartV2.rawValue
        ]
        guard supportedSchemas.contains(payload.schemaVersion) else {
            return false
        }
        if let dayString = payload.helmDay,
           let parsed = parseHelmDay(dayString),
           parsed != helmDay {
            return false
        }

        if payload.hasDetailedSets {
            let plan = try WorkoutStartPlanBuilder.importedPlan(from: payload, persistence: persistence)
            try await onStart(.importedPlan(plan))
            return true
        }

        let useAdjusted = payload.useAdjustedPrescription ?? false
        if let exercises = payload.exercises, !exercises.isEmpty {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let base = try await prescriptionService.todaysPrescription(readiness: readiness)
            if let adjusted = try WorkoutStartPrescriptionResolver.prescription(
                exerciseLabels: payload.exerciseLabels,
                base: base,
                persistence: persistence
            ) {
                PrescriptionDayStore.save(adjusted, for: helmDay)
            } else if payload.schemaVersion == CoachOutputSchemaVersion.workoutStartV2.rawValue {
                let plan = try WorkoutStartPlanBuilder.importedPlan(from: payload, persistence: persistence)
                try await onStart(.importedPlan(plan))
                return true
            }
        }

        try await onStart(.prescription(useAdjusted: useAdjusted || payload.exercises != nil))
        return true
    }

    private static func parseHelmDay(_ value: String) -> HelmDay? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }
}
