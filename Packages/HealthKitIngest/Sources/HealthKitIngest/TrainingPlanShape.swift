import Persistence
import PlanKit

/// Resolves the live week rotation from persisted plan settings.
enum TrainingPlanShape {
    static func dayKindRotation(from settings: StoredTrainingPlanSettings) -> [TrainingDayKind] {
        let parsed = settings.dayKindRotationRaw.compactMap(TrainingDayKind.init(rawValue:))
        if parsed.count >= 2 {
            return parsed
        }
        let template = ProgramTemplate(rawValue: settings.programTemplateRaw) ?? .ppl
        return template.defaultDayKindRotation(daysPerWeek: settings.daysPerWeek)
    }
}
