import Foundation

/// Fixed engine anchors the coach may cite. Single source of truth for validation
/// and prompt generation -- consumers must not duplicate the list.
public enum EngineAnchor: String, CaseIterable, Sendable {
    case progression
    case readiness
    case deload
    case nutrition
    case scheduling
    case autoregulation

    public var displayLabel: String {
        switch self {
        case .progression: return "Prescription Engine"
        case .readiness: return "Readiness Model"
        case .deload: return "Deload Policy"
        case .nutrition: return "Nutrition Engine"
        case .scheduling: return "Scheduling Engine"
        case .autoregulation: return "Autoregulation Engine"
        }
    }

    /// Set of raw values for O(1) membership checks.
    public static let allRawValues: Set<String> = Set(allCases.map(\.rawValue))

    /// Prompt-friendly anchor list for the system prompt.
    public static let promptList: String = allCases
        .map { "[engine:\($0.rawValue)]" }
        .joined(separator: " or ")
}
