import CoachLLM
import Core
import Foundation
import HealthKitIngest
import Persistence

enum CoachWorkoutStartAdjuster {
    @MainActor
    static func tryStartFromEmbeddedJSON(
        in text: String,
        helmDay: HelmDay,
        persistence: PersistenceStore,
        prescriptionService: PrescriptionService,
        onStart: @MainActor (_ useAdjustedPrescription: Bool) async throws -> Void
    ) async throws -> Bool {
        guard let payload = WorkoutStartPayloadParser.parse(from: text) else { return false }
        guard payload.schemaVersion == CoachOutputSchemaVersion.workoutStartV1.rawValue else {
            return false
        }
        if let dayString = payload.helmDay,
           let parsed = parseHelmDay(dayString),
           parsed != helmDay {
            return false
        }

        let useAdjusted = payload.useAdjustedPrescription ?? false
        if let exercises = payload.exercises, !exercises.isEmpty {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let base = try await prescriptionService.todaysPrescription(readiness: readiness)
            if let adjusted = try WorkoutStartPrescriptionResolver.prescription(
                exerciseLabels: exercises,
                base: base,
                persistence: persistence
            ) {
                PrescriptionDayStore.save(adjusted, for: helmDay)
            }
        }

        try await onStart(useAdjusted || payload.exercises != nil)
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
