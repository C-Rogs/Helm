import Foundation

/// Athlete-facing recovery guidance keyed by joint id (engine-agnostic).
///
/// Pattern exclusion lives in PlanKit (`StandingConstraintPatternPolicy`); this catalog
/// only describes what to soft-pause in copy so Core stays free of movement patterns.
public enum JointRecoveryCatalog: Sendable {
    /// Canonical joint ids the coach/engine understand.
    public static let knownJoints: Set<String> = [
        "shoulder", "knee", "hip", "elbow", "wrist", "back", "ankle", "neck", "general"
    ]

    /// Short phrase for active-window rationale (nil → warm-up/ease only, no named pause).
    public static func softPausePhrase(for joint: String) -> String? {
        switch normalize(joint) {
        case "shoulder": return "overhead pressing"
        case "knee": return "deep knee bends (squats / lunges)"
        case "hip": return "heavy hinging"
        case "elbow": return "direct elbow-loaded arm work"
        case "wrist": return "heavy gripping and wrist-loaded pressing"
        case "back": return "fatigued spinal loading"
        case "ankle": return "high-impact ankle loading"
        case "neck": return "loaded neck / overhead positions that aggravate it"
        default: return nil
        }
    }

    public static func normalize(_ joint: String) -> String {
        let value = joint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "shoulders": return "shoulder"
        case "knees": return "knee"
        case "hips": return "hip"
        case "elbows": return "elbow"
        case "wrists": return "wrist"
        case "ankles": return "ankle"
        case "lumbar", "low back", "lower back": return "back"
        default: return value
        }
    }

    public static func activeWindowNote(joint: String, until: HelmDay) -> String {
        let id = normalize(joint)
        let label = id == "general" ? "Joint" : id.capitalized
        if let pause = softPausePhrase(for: id) {
            return "\(label) recovery window through \(until.formatted): soft pause \(pause); warm up and stretch."
        }
        return "\(label) recovery window through \(until.formatted): warm up and stretch; ease related loading."
    }

    public static func easeBackNote(joint: String) -> String {
        let id = normalize(joint)
        let label = id == "general" ? "Joint" : id.capitalized
        if let pause = softPausePhrase(for: id) {
            return "\(label) recently noted - warm up thoroughly; \(pause) is allowed again."
        }
        return "\(label) recently noted - warm up thoroughly as you ease back."
    }
}
