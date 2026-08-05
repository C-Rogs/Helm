import Core
import Foundation

/// Maps active recovery joints to PlanKit movement patterns to soft-exclude.
public enum StandingConstraintPatternPolicy: Sendable {
    public static func excludedPatterns(forActiveJoints joints: Set<String>) -> Set<MovementPatternKind> {
        var excluded = Set<MovementPatternKind>()
        for raw in joints {
            let joint = JointRecoveryCatalog.normalize(raw)
            excluded.formUnion(softExcludedPatterns(for: joint))
        }
        return excluded
    }

    public static func softExcludedPatterns(for joint: String) -> Set<MovementPatternKind> {
        switch JointRecoveryCatalog.normalize(joint) {
        case "shoulder":
            [.verticalPress]
        case "knee":
            [.kneeExtensionCompound, .unilateralKnee]
        case "hip":
            [.hipHinge]
        case "elbow":
            [.elbowFlexion, .tricepsIsolation]
        case "back":
            [.hipHinge]
        case "ankle":
            [.calf]
        case "wrist", "neck", "general":
            []
        default:
            []
        }
    }
}
