import Core
import CoachLLM
import Foundation
import Persistence
import PlanKit

struct SettingsAdjustmentPayload: Codable, Sendable, Equatable {
    let schemaVersion: String
    let phase: String?
    let weeklyRateKg: Double?
    let emphasis: String?
    let rationale: String?
}

enum CoachPlanSettingsAdjuster {
    static func tryApplyEmbeddedJSON(in text: String, persistence: PersistenceStore) throws -> Bool {
        guard let json = extractJSONObject(from: text) else { return false }
        let data = try JSONSerialization.data(withJSONObject: json)
        let payload = try JSONDecoder().decode(SettingsAdjustmentPayload.self, from: data)
        guard payload.schemaVersion == CoachOutputSchemaVersion.settingsAdjustmentV1.rawValue else {
            return false
        }
        try apply(payload, persistence: persistence)
        return true
    }

    static func apply(_ payload: SettingsAdjustmentPayload, persistence: PersistenceStore) throws {
        var settings = try persistence.trainingPlan.load()
        let current = settings.phaseGoal
        let phase = payload.phase.flatMap(TrainingPhase.init(rawValue:)) ?? current.phase
        settings.phaseGoal = PhaseGoal(
            phase: phase,
            weeklyRateKg: payload.weeklyRateKg ?? current.weeklyRateKg,
            targetMass: current.targetMass,
            emphasis: payload.emphasis ?? current.emphasis
        )
        try persistence.trainingPlan.save(settings)
    }

    private static func extractJSONObject(from text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return nil
        }
        let snippet = String(text[start ... end])
        guard let data = snippet.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schemaVersion"] as? String == CoachOutputSchemaVersion.settingsAdjustmentV1.rawValue
        else {
            return nil
        }
        return object
    }
}
