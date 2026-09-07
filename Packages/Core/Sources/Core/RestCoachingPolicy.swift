import Foundation

/// Rest-timer coach phases. Copy stays rare and terse; haptics stay on the existing rest path.
public enum RestCoachingPhase: Sendable, Hashable {
    case start
    case mid
    case windDown
    case expired
}

public enum RestCoachingPolicy {
    /// Default last-N seconds for wind-down on normal rests.
    public static let windDownThresholdSeconds = 10

    public static func phase(remainingSeconds: Int, totalSeconds: Int) -> RestCoachingPhase {
        if remainingSeconds <= 0 { return .expired }

        let total = max(1, totalSeconds)
        // Scale wind-down on short rests so mid still has a window (e.g. 15s → 5s).
        let windDown = min(windDownThresholdSeconds, max(3, total / 3))
        if remainingSeconds <= windDown { return .windDown }

        let elapsed = max(0, total - remainingSeconds)
        let startWindow = min(25, max(8, total / 4))
        if elapsed < startWindow { return .start }
        return .mid
    }

    /// Instrument coach line for the phase. Optional up-next name and form cue only when short.
    public static func line(
        phase: RestCoachingPhase,
        upNextName: String? = nil,
        formCue: String? = nil
    ) -> String {
        let next = trimmedName(upNextName)
        let cue = shortCue(formCue)

        switch phase {
        case .start:
            if let next {
                return "Recover. Up next · \(next)."
            }
            return "Recover. Reset your setup."
        case .mid:
            if let cue {
                return cue
            }
            return "Stay loose. Breathe."
        case .windDown:
            if let next {
                return "Almost. Get set for \(next)."
            }
            return "Almost. Get set."
        case .expired:
            if let next {
                return "Rest done. Go · \(next)."
            }
            return "Rest done. Hit the next set."
        }
    }

    private static func trimmedName(_ name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return name
    }

    /// Prefer a single short sentence so the rest dock stays compact.
    private static func shortCue(_ cue: String?) -> String? {
        guard let raw = cue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let sentence: String
        if let dot = raw.firstIndex(of: ".") {
            sentence = String(raw[...dot]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            sentence = raw
        }
        guard !sentence.isEmpty, sentence.count <= 56 else { return nil }
        return sentence
    }
}
