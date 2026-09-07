import Foundation

/// Direction of a dual-signal input over the comparison window.
public enum RecompSignalDirection: String, Sendable, Hashable, Codable, CaseIterable {
    case rising
    case flat
    case falling
    case unknown
}

/// Inputs for the recomp / dual-signal classifier.
public struct RecompStorySignals: Sendable, Hashable, Equatable {
    public var weight: RecompSignalDirection
    public var strength: RecompSignalDirection
    public var volume: RecompSignalDirection
    public var bodyFat: RecompSignalDirection

    public init(
        weight: RecompSignalDirection = .unknown,
        strength: RecompSignalDirection = .unknown,
        volume: RecompSignalDirection = .unknown,
        bodyFat: RecompSignalDirection = .unknown
    ) {
        self.weight = weight
        self.strength = strength
        self.volume = volume
        self.bodyFat = bodyFat
    }
}

/// Classified recomp story for instrument UI.
public struct RecompStory: Sendable, Hashable, Equatable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case insufficient
        case recompStrength
        case recompBodyFat
        case recompVolume
        case fatLossFriendly
        case surplusWorking
        case scaleSteady
        case scaleOnly
    }

    public var kind: Kind
    public var headline: String
    public var detail: String?

    public init(kind: Kind, headline: String, detail: String? = nil) {
        self.kind = kind
        self.headline = headline
        self.detail = detail
    }

    public var isEmptyState: Bool { kind == .insufficient }
}

/// Pure slope helper for series → direction.
public enum RecompSignalMath {
    /// Compare newer vs older sample with an absolute flat band.
    public static func direction(
        newer: Double?,
        older: Double?,
        flatAbsolute: Double
    ) -> RecompSignalDirection {
        guard let newer, let older, newer.isFinite, older.isFinite, flatAbsolute >= 0 else {
            return .unknown
        }
        let delta = newer - older
        if abs(delta) <= flatAbsolute { return .flat }
        return delta > 0 ? .rising : .falling
    }

    /// Uses first and last values of an oldest-first series.
    public static func directionFromSeries(
        _ valuesOldestFirst: [Double],
        flatAbsolute: Double
    ) -> RecompSignalDirection {
        guard valuesOldestFirst.count >= 2 else { return .unknown }
        return direction(
            newer: valuesOldestFirst.last,
            older: valuesOldestFirst.first,
            flatAbsolute: flatAbsolute
        )
    }
}

/// BWS-style recomp detector: scale vs strength / volume / body-fat.
public enum RecompStoryClassifier {
    public static func classify(_ signals: RecompStorySignals) -> RecompStory {
        let hasSecondSignal =
            signals.strength != .unknown
            || signals.volume != .unknown
            || signals.bodyFat != .unknown

        if signals.weight == .unknown && !hasSecondSignal {
            return RecompStory(
                kind: .insufficient,
                headline: "Not enough dual-signal data yet.",
                detail: "Keep logging scale weight and lifts. Body fat from Health helps too."
            )
        }

        if signals.weight == .flat {
            if signals.strength == .rising {
                return RecompStory(
                    kind: .recompStrength,
                    headline: "Scale flat. Strength is climbing.",
                    detail: "Body weight held while e1RM moved up. Classic recomp signal."
                )
            }
            if signals.bodyFat == .falling {
                return RecompStory(
                    kind: .recompBodyFat,
                    headline: "Scale flat. Body fat is trending down.",
                    detail: "Weight steady while composition improves."
                )
            }
            if signals.volume == .rising {
                return RecompStory(
                    kind: .recompVolume,
                    headline: "Scale flat. Training volume is climbing.",
                    detail: "Weight held while weekly hard sets rose."
                )
            }
            if hasSecondSignal {
                return RecompStory(
                    kind: .scaleSteady,
                    headline: "Scale is steady.",
                    detail: "Waiting on a clearer strength or composition move."
                )
            }
            return RecompStory(
                kind: .scaleOnly,
                headline: "Scale is steady.",
                detail: "Add lifts or body fat readings for a second signal."
            )
        }

        if signals.weight == .falling {
            if signals.volume == .flat || signals.volume == .rising || signals.strength == .rising {
                return RecompStory(
                    kind: .fatLossFriendly,
                    headline: "Scale is down. Training is holding.",
                    detail: "Fat-loss friendly: weight dropping without volume collapse."
                )
            }
            return RecompStory(
                kind: .scaleOnly,
                headline: "Scale is trending down.",
                detail: hasSecondSignal
                    ? "Watch volume so the cut stays muscle-friendly."
                    : "Log sessions so strength can confirm the cut."
            )
        }

        if signals.weight == .rising {
            if signals.strength == .rising {
                return RecompStory(
                    kind: .surplusWorking,
                    headline: "Scale up. Strength is climbing.",
                    detail: "Surplus looks productive."
                )
            }
            return RecompStory(
                kind: .scaleOnly,
                headline: "Scale is trending up.",
                detail: hasSecondSignal
                    ? "Check whether strength and volume keep pace."
                    : "Log lifts to see if the surplus is working."
            )
        }

        // Weight unknown but second signal present.
        if signals.strength == .rising {
            return RecompStory(
                kind: .scaleOnly,
                headline: "Strength is climbing.",
                detail: "Need a clearer scale trend to call recomp."
            )
        }
        if signals.bodyFat == .falling {
            return RecompStory(
                kind: .scaleOnly,
                headline: "Body fat is trending down.",
                detail: "Need a clearer scale trend to call recomp."
            )
        }

        return RecompStory(
            kind: .insufficient,
            headline: "Not enough dual-signal data yet.",
            detail: "Keep logging scale weight and lifts. Body fat from Health helps too."
        )
    }
}
