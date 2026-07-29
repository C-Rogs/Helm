import CoachLLM
import Core
import Foundation

struct WorkoutStartPayload: Codable, Sendable, Equatable {
    let schemaVersion: String
    let helmDay: String?
    let useAdjustedPrescription: Bool?
}

enum CoachWorkoutStartAdjuster {
    @MainActor
    static func tryStartFromEmbeddedJSON(
        in text: String,
        helmDay: HelmDay,
        onStart: @MainActor (_ useAdjustedPrescription: Bool) async throws -> Void
    ) async throws -> Bool {
        guard let payload = extractPayload(from: text) else { return false }
        guard payload.schemaVersion == CoachOutputSchemaVersion.workoutStartV1.rawValue else {
            return false
        }
        if let dayString = payload.helmDay,
           let parsed = parseHelmDay(dayString),
           parsed != helmDay {
            return false
        }
        let useAdjusted = payload.useAdjustedPrescription ?? false
        try await onStart(useAdjusted)
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

    private static func extractPayload(from text: String) -> WorkoutStartPayload? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return nil
        }
        let snippet = String(text[start ... end])
        guard let data = snippet.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkoutStartPayload.self, from: data)
    }
}
