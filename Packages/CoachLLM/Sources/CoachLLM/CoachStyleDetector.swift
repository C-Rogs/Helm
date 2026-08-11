import Foundation

/// Client-side heuristics that analyse athlete messages to detect
/// voice/style preferences. Runs in Swift, not the LLM (PrefEval ICLR 2025
/// showed LLMs are bad at implicit preference inference).
public enum CoachStyleDetector: Sendable {

    /// Running style estimate used for EMA smoothing across turns.
    private static let emaAlpha: Double = 0.3
    private static let deadBand: Double = 0.1
    private static let capPerTurn: Double = 0.25

    private struct RawScores: Sendable {
        var detail: Double  // 0=terse ... 1=thorough
        var depth: Double   // 0=lay ... 1=scientific
        var encouragement: Double  // 0=neutral ... 1=supportive
        var directive: Double  // 0=suggestive ... 1=prescriptive
    }

    /// Technical term stems used to detect scientific vocabulary.
    private static let technicalStems: Set<String> = [
        "hypertroph", "atroph", "sarcoplasm", "myofibril", "motor unit",
        "recruit", "rpe", "rm", "trimp", "hrv", "vo2", "mrv", "mev",
        "periodi", "mesocycle", "microcycle", "progressive overload",
        "autoregul", "deload", "catecholamin", "cortisol", "testosteron",
        "glycogen", "gluconeogen", "lipolys", "oxidat", "anaerobic",
        "aerobic", "atp", "creatine", "eccentric", "concentric",
        "isometric", "tempo", "amrap", "emom", "hiit", "liss"
    ]

    /// Detect style from a single athlete message and update the EMA-smoothed profile.
    public static func update(
        profile: inout CoachStyleProfile?,
        from message: String,
        turnIndex: Int
    ) {
        let raw = extractRawScores(from: message)
        var current = profile ?? CoachStyleProfile()

        func ema(_ prev: Double, _ new: Double) -> Double {
            let capped = max(prev - capPerTurn, min(prev + capPerTurn, new))
            let smoothed = prev * (1 - emaAlpha) + capped * emaAlpha
            let diff = abs(smoothed - prev)
            return diff < deadBand ? prev : smoothed
        }

        let detailScore = ema(detailToDouble(current.detail), raw.detail)
        let depthScore = ema(depthToDouble(current.depth), raw.depth)
        let encScore = ema(encouragementToDouble(current.encouragement), raw.encouragement)
        let dirScore = ema(directiveToDouble(current.directive), raw.directive)

        current.detail = doubleToDetail(detailScore)
        current.depth = doubleToDepth(depthScore)
        current.encouragement = doubleToEncouragement(encScore)
        current.directive = doubleToDirective(dirScore)
        current.lastUpdated = .now
        current.source = .heuristic

        profile = current
    }

    // MARK: - Raw extraction

    private static func extractRawScores(from message: String) -> RawScores {
        let words = message.split(separator: " ").map(String.init)
        let wordCount = Double(words.count)

        let detail: Double = {
            if wordCount <= 5 { return 0.0 }
            if wordCount >= 50 { return 1.0 }
            return (wordCount - 5) / 45.0
        }()

        let depth: Double = {
            guard wordCount > 0 else { return 0.0 }
            let lower = message.lowercased()
            var hits = 0
            for stem in technicalStems {
                if lower.contains(stem) { hits += 1 }
            }
            let ratio = Double(hits) / wordCount
            let normalized = ratio / 0.08  // target: 0.02-0.08 range maps to 0.25-1.0
            return max(0, min(1, normalized))
        }()

        let encouragement: Double = {
            let positiveEmoji = ["💪", "👊", "😊", "🙌", "🎯", "✅", "🔥", "❤️"]
            var hits = 0
            for emoji in positiveEmoji where message.contains(emoji) { hits += 1 }
            return max(0, min(1, Double(hits) / 3.0))
        }()

        let directive: Double = {
            let imperatives = ["tell me", "what should i", "prescribe", "give me",
                               "how many", "how much", "exactly", "specifically"]
            var hits = 0
            let lower = message.lowercased()
            for imp in imperatives where lower.contains(imp) { hits += 1 }
            return max(0, min(1, Double(hits) / 2.0))
        }()

        return RawScores(
            detail: detail,
            depth: depth,
            encouragement: encouragement,
            directive: directive
        )
    }

    // MARK: - Scalar <-> Enum mapping

    private static func detailToDouble(_ d: CoachStyleProfile.Detail) -> Double {
        switch d {
        case .brief: return 0.0
        case .balanced: return 0.5
        case .thorough: return 1.0
        }
    }

    private static func depthToDouble(_ d: CoachStyleProfile.Depth) -> Double {
        switch d {
        case .lay: return 0.0
        case .mixed: return 0.5
        case .scientific: return 1.0
        }
    }

    private static func encouragementToDouble(_ e: CoachStyleProfile.Encouragement) -> Double {
        switch e {
        case .neutral: return 0.0
        case .balanced: return 0.5
        case .supportive: return 1.0
        }
    }

    private static func directiveToDouble(_ d: CoachStyleProfile.Directive) -> Double {
        switch d {
        case .suggestive: return 0.0
        case .balanced: return 0.5
        case .prescriptive: return 1.0
        }
    }

    private static func doubleToDetail(_ v: Double) -> CoachStyleProfile.Detail {
        if v < 0.33 { return .brief }
        if v < 0.67 { return .balanced }
        return .thorough
    }

    private static func doubleToDepth(_ v: Double) -> CoachStyleProfile.Depth {
        if v < 0.33 { return .lay }
        if v < 0.67 { return .mixed }
        return .scientific
    }

    private static func doubleToEncouragement(_ v: Double) -> CoachStyleProfile.Encouragement {
        if v < 0.33 { return .neutral }
        if v < 0.67 { return .balanced }
        return .supportive
    }

    private static func doubleToDirective(_ v: Double) -> CoachStyleProfile.Directive {
        if v < 0.33 { return .suggestive }
        if v < 0.67 { return .balanced }
        return .prescriptive
    }
}
