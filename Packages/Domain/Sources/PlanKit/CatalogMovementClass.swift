import Foundation

/// Coarse catalog class from seed / picker mapping. Finer session slots live on `MovementPatternKind`.
public enum CatalogMovementClass: String, Sendable, Hashable, Codable, CaseIterable {
    case squat
    case hinge
    case lunge
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case carry
    case isolation
    case cardio
    case core
    case other

    /// Parse seed or DB strings. Unknown non-empty values become `other` (keyword fallback, not a hard exclude).
    public static func parse(_ raw: String?) -> CatalogMovementClass? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let exact = CatalogMovementClass(rawValue: trimmed) {
            return exact
        }
        switch trimmed.lowercased().replacingOccurrences(of: "_", with: "") {
        case "squat": return .squat
        case "hinge": return .hinge
        case "lunge": return .lunge
        case "horizontalpush": return .horizontalPush
        case "verticalpush": return .verticalPush
        case "horizontalpull": return .horizontalPull
        case "verticalpull": return .verticalPull
        case "carry": return .carry
        case "isolation": return .isolation
        case "cardio": return .cardio
        case "core": return .core
        default: return .other
        }
    }
}
