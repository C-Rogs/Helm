import Foundation

/// Maps athlete recovery language ("arms sore") to day-kinds that should be deferred.
/// Distinct from long-term emphasis / prioritize.
public enum TrainingDayRecoveryMap {
    private static let regionTokens: [(token: String, kinds: [TrainingDayKind])] = [
        ("arms", [.push, .pull, .arms, .upper]),
        ("arm", [.push, .pull, .arms, .upper]),
        ("elbows", [.push, .arms, .upper]),
        ("elbow", [.push, .arms, .upper]),
        ("triceps", [.push, .arms, .upper]),
        ("tricep", [.push, .arms, .upper]),
        ("biceps", [.pull, .arms, .upper]),
        ("bicep", [.pull, .arms, .upper]),
        ("chest", [.push, .upper]),
        ("pecs", [.push, .upper]),
        ("pec", [.push, .upper]),
        ("shoulders", [.push, .upper]),
        ("shoulder", [.push, .upper]),
        ("press", [.push, .upper]),
        ("lats", [.pull, .upper]),
        ("lat", [.pull, .upper]),
        ("back", [.pull, .upper]),
        ("hamstrings", [.legs, .lower]),
        ("hamstring", [.legs, .lower]),
        ("glutes", [.legs, .lower]),
        ("glute", [.legs, .lower]),
        ("quads", [.legs, .lower]),
        ("quad", [.legs, .lower]),
        ("knees", [.legs, .lower]),
        ("knee", [.legs, .lower]),
        ("calves", [.legs, .lower]),
        ("calf", [.legs, .lower]),
        ("legs", [.legs, .lower]),
        ("leg", [.legs, .lower]),
        ("upper", [.upper, .push, .pull, .arms]),
        ("lower", [.lower, .legs]),
        ("push", [.push]),
        ("pull", [.pull])
    ]

    /// Day kinds that heavily load the named region, filtered to the active rotation.
    public static func deferredKinds(
        forRegion region: String,
        among rotation: [TrainingDayKind]
    ) -> [TrainingDayKind] {
        let allowed = Set(rotation.isEmpty ? TrainingDayKind.allCases : rotation)
        let candidates = conflictingKinds(forRegion: region).filter { allowed.contains($0) }
        return candidates
    }

    /// Unfiltered conflict list for free-text recovery language.
    public static func conflictingKinds(forRegion region: String) -> [TrainingDayKind] {
        let lower = region
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
        guard lower.isEmpty == false else { return [] }

        // Prefer longer token matches anywhere in the phrase ("sore arms", "tight hamstrings").
        for entry in regionTokens.sorted(by: { $0.token.count > $1.token.count }) {
            if lower == entry.token || lower.split(separator: " ").map(String.init).contains(entry.token)
                || lower.contains(entry.token)
            {
                return entry.kinds
            }
        }
        return []
    }

    /// Prefer a clean day after deferrals: first rotation kind not deferred and not yet consumed.
    public static func preferredKind(
        rotation: [TrainingDayKind],
        deferred: Set<TrainingDayKind>,
        consumed: [TrainingDayKind]
    ) -> TrainingDayKind? {
        let cycle = rotation.isEmpty ? [.push, .pull, .legs] : rotation
        var remaining = cycle
        for kind in consumed {
            if let index = remaining.firstIndex(of: kind) {
                remaining.remove(at: index)
            } else if remaining.isEmpty == false {
                remaining.removeFirst()
            }
        }
        if let next = remaining.first(where: { !deferred.contains($0) }) {
            return next
        }
        return cycle.first(where: { !deferred.contains($0) })
    }

    /// Human labels for confirm cards.
    public static func deferredLabels(
        forRegion region: String?,
        kinds: [String]?,
        among rotation: [TrainingDayKind]
    ) -> [String] {
        var deferred = Set<TrainingDayKind>()
        if let kinds {
            for raw in kinds {
                if let kind = TrainingDayKind(rawValue: raw.lowercased()) {
                    deferred.insert(kind)
                }
            }
        }
        if let region, region.isEmpty == false {
            deferred.formUnion(deferredKinds(forRegion: region, among: rotation))
        }
        return deferred.map(\.label).sorted()
    }
}
