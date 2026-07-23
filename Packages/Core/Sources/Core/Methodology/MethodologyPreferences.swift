import Foundation

/// Structured training-methodology preferences stored inside `MemoryProfile.preferences`.
public struct MethodologyPreferences: Sendable, Hashable, Codable, Equatable {
    public enum SelectionBias: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
        case balanced
        case stretch
        case stimulusToFatigue

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .balanced: "Balanced"
            case .stretch: "Stretch bias"
            case .stimulusToFatigue: "Low fatigue bias"
            }
        }

        public var detail: String {
            switch self {
            case .balanced:
                "Balance effectiveness, stretch position, and stimulus-to-fatigue."
            case .stretch:
                "Favour movements with a strong stretch-position stimulus."
            case .stimulusToFatigue:
                "Favour movements with lower joint and systemic fatigue."
            }
        }
    }

    public static let equipmentOptions: [String] = [
        "barbell",
        "dumbbell",
        "cable",
        "machine",
        "kettlebell",
        "band",
        "bodyweight"
    ]

    /// Empty set means all equipment is allowed.
    public var allowedEquipment: Set<String>
    public var selectionBias: SelectionBias

    public init(
        allowedEquipment: Set<String> = [],
        selectionBias: SelectionBias = .balanced
    ) {
        self.allowedEquipment = allowedEquipment
        self.selectionBias = selectionBias
    }

    public static let `default` = MethodologyPreferences()

    private static let equipmentKey = "equipment"
    private static let selectionBiasKey = "selectionbias"

    public static func parse(from preferencesText: String) -> (preferences: MethodologyPreferences, freeform: String) {
        var allowedEquipment = Set<String>()
        var selectionBias = SelectionBias.balanced
        var freeformLines: [String] = []

        for rawLine in preferencesText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let separator = line.firstIndex(of: "=") else {
                if !line.isEmpty {
                    freeformLines.append(line)
                }
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)

            switch key {
            case equipmentKey:
                let tags = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
                allowedEquipment = Set(tags)
            case selectionBiasKey:
                if let parsed = SelectionBias(rawValue: value) {
                    selectionBias = parsed
                }
            default:
                freeformLines.append(line)
            }
        }

        return (
            MethodologyPreferences(
                allowedEquipment: allowedEquipment,
                selectionBias: selectionBias
            ),
            freeformLines.joined(separator: "\n")
        )
    }

    public func merge(into preferencesText: String) -> String {
        let parsed = Self.parse(from: preferencesText)
        var lines = parsed.freeform
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if !allowedEquipment.isEmpty {
            let equipmentLine = allowedEquipment.sorted().joined(separator: ",")
            lines.append("\(Self.equipmentKey)=\(equipmentLine)")
        }
        if selectionBias != .balanced {
            lines.append("selectionBias=\(selectionBias.rawValue)")
        }

        return lines.joined(separator: "\n")
    }

    public var availableEquipmentFilter: Set<String>? {
        allowedEquipment.isEmpty ? nil : allowedEquipment
    }
}
