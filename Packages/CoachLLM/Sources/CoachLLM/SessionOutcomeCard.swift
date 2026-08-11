import Foundation

/// A session-level outcome produced after a workout completes,
/// comparing prescribed targets to actual performance.
public struct SessionOutcomeCard: Sendable, Hashable, Codable, Equatable {
    public var helmDay: String
    public var sessionType: String
    public var id: UUID
    public var durationMinutes: Int
    public var estimatedTRIMP: Double
    public var completed: Bool
    public var exercises: [ExerciseOutcome]
    public var attributedMessageID: String?
    public var prescribedBy: PrescriptionSource
    public var sessionRPE: Double?
    public var atypicalFlags: [String]

    public init(
        helmDay: String,
        sessionType: String,
        id: UUID = UUID(),
        durationMinutes: Int = 0,
        estimatedTRIMP: Double = 0,
        completed: Bool = true,
        exercises: [ExerciseOutcome] = [],
        attributedMessageID: String? = nil,
        prescribedBy: PrescriptionSource = .engine,
        sessionRPE: Double? = nil,
        atypicalFlags: [String] = []
    ) {
        self.helmDay = helmDay
        self.sessionType = sessionType
        self.id = id
        self.durationMinutes = durationMinutes
        self.estimatedTRIMP = estimatedTRIMP
        self.completed = completed
        self.exercises = exercises
        self.attributedMessageID = attributedMessageID
        self.prescribedBy = prescribedBy
        self.sessionRPE = sessionRPE
        self.atypicalFlags = atypicalFlags
    }

    public struct ExerciseOutcome: Sendable, Hashable, Codable, Equatable {
        public var name: String
        public var prescribedSets: Int
        public var completedSets: Int
        public var prescribedKg: Double?
        public var actualKg: Double?
        public var prescribedRPE: Double?
        public var actualRPE: Double?
        public var deviations: [Deviation]

        public init(
            name: String,
            prescribedSets: Int,
            completedSets: Int,
            prescribedKg: Double? = nil,
            actualKg: Double? = nil,
            prescribedRPE: Double? = nil,
            actualRPE: Double? = nil,
            deviations: [Deviation] = []
        ) {
            self.name = name
            self.prescribedSets = prescribedSets
            self.completedSets = completedSets
            self.prescribedKg = prescribedKg
            self.actualKg = actualKg
            self.prescribedRPE = prescribedRPE
            self.actualRPE = actualRPE
            self.deviations = deviations
        }

        public enum Deviation: String, Sendable, Hashable, Codable {
            case loadDropped
            case loadExceeded
            case volumeSkipped
            case volumeExtra
            case exerciseSkipped
            case exerciseAdded
            case matched

            public var displayLabel: String {
                switch self {
                case .loadDropped: return "Load ↓"
                case .loadExceeded: return "Load ↑"
                case .volumeSkipped: return "Skipped"
                case .volumeExtra: return "Extra"
                case .exerciseSkipped: return "Skipped"
                case .exerciseAdded: return "Added"
                case .matched: return "On plan"
                }
            }
        }
    }

    public enum PrescriptionSource: String, Sendable, Hashable, Codable {
        case engine
        case coachCustom
        case adHoc
    }
}

// MARK: - LLM display formatting

extension SessionOutcomeCard {
    /// Formats the outcome card as structured natural language for the LLM prompt.
    /// Compact, high-signal, ~85 tokens per session.
    public var llmText: String {
        var lines: [String] = []

        let finishStatus = completed ? "finished" : "abandoned"
        lines.append("\(helmDay) \(sessionType) | \(durationMinutes) min | TRIMP \(String(format: "%.0f", estimatedTRIMP)) | \(finishStatus)")

        for ex in exercises {
            let kgPart: String = {
                guard let rx = ex.prescribedKg else { return "" }
                guard let actual = ex.actualKg else { return "" }
                if abs(rx - actual) > 0.5 {
                    let diff = actual - rx
                    let sign = diff >= 0 ? "+" : ""
                    let diffStr = String(format: "%.0f", abs(diff))
                    return "\(String(format: "%.0f", actual))kg (rx:\(String(format: "%.0f", rx))kg \(sign)\(diffStr)kg)"
                } else {
                    return "\(String(format: "%.0f", actual))kg (rx:\(String(format: "%.0f", rx))kg matched)"
                }
            }()

            let rpePart: String = {
                guard let rx = ex.prescribedRPE, let act = ex.actualRPE else { return "" }
                let diff = act - rx
                let sign = diff >= 0 ? "+" : ""
                return "RPE \(String(format: "%.0f", rx))->\(String(format: "%.0f", act)) (\(sign)\(String(format: "%.1f", abs(diff))))"
            }()

            var parts = ["\(ex.name): \(ex.completedSets)/\(ex.prescribedSets) sets"]
            if !kgPart.isEmpty { parts.append(kgPart) }
            if !rpePart.isEmpty { parts.append(rpePart) }
            lines.append(parts.joined(separator: ", "))
        }

        if let rpe = sessionRPE {
            lines.append("Session RPE: \(String(format: "%.1f", rpe)) | Rx source: \(prescribedBy.rawValue)")
        }

        if !atypicalFlags.isEmpty {
            lines.append("Atypical: " + atypicalFlags.joined(separator: " | "))
        }

        return lines.joined(separator: "\n")
    }

    /// Weekly adherence summary line (~30 tokens).
    public static func weeklyAdherenceLine(from cards: [SessionOutcomeCard]) -> String {
        guard !cards.isEmpty else { return "" }
        let completed = cards.filter(\.completed).count
        var parts = ["Recent adherence: \(completed)/\(cards.count) sessions complete."]

        // Count exercises with no negative deviations.
        var totalMatched = 0
        var totalExercises = 0
        for card in cards {
            for ex in card.exercises {
                totalExercises += 1
                let negativeDeviations: Set<SessionOutcomeCard.ExerciseOutcome.Deviation> = [
                    .loadDropped, .volumeSkipped, .exerciseSkipped
                ]
                if Set(ex.deviations).isDisjoint(with: negativeDeviations) {
                    totalMatched += 1
                }
            }
        }
        if totalExercises > 0 {
            let pct = Int((Double(totalMatched) / Double(totalExercises)) * 100)
            parts.append("Load match: \(pct)%")
        }

        return parts.joined(separator: " ")
    }
}
