import Foundation

/// Formats the Progress hub / Dashboard journey line: `Week N · Hypertrophy · Cut`.
public enum PhaseNarrativeFormatter {
    /// Builds a middle-dot journey string from mesocycle week + training phase + goal.
    ///
    /// - Parameters:
    ///   - currentWeek: Mesocycle week when known.
    ///   - blockLengthWeeks: Optional block length; only shown when `includeBlockLength` is true.
    ///   - includeBlockLength: Prefer `Week N of M` when both week and length exist.
    ///   - mesocyclePhase: Raw mesocycle label (`Accumulating` / `Deload`); mapped for display.
    ///   - experienceLabel: Fallback training language when mesocycle phase is missing.
    ///   - goalPhase: Goal label (`Cut` / `Gain` / `Maintain`, optionally with emphasis).
    ///   - weeklyRateKg: Absolute weekly rate from settings; signed from goal phase.
    public static func string(
        currentWeek: Int?,
        blockLengthWeeks: Int? = nil,
        includeBlockLength: Bool = false,
        mesocyclePhase: String? = nil,
        experienceLabel: String? = nil,
        goalPhase: String? = nil,
        weeklyRateKg: Double? = nil
    ) -> String {
        var parts: [String] = []

        if let currentWeek {
            if includeBlockLength, let blockLengthWeeks {
                parts.append("Week \(currentWeek) of \(blockLengthWeeks)")
            } else {
                parts.append("Week \(currentWeek)")
            }
        }

        if let training = displayTrainingPhase(
            mesocyclePhase: mesocyclePhase,
            experienceLabel: experienceLabel
        ) {
            parts.append(training)
        }

        let goalPrimary = primaryGoalLabel(goalPhase)
        if let goalPrimary {
            parts.append(goalPrimary)
        }

        if let weeklyRateKg, let rate = formatWeeklyRate(weeklyRateKg, goalPhase: goalPrimary) {
            parts.append(rate)
        }

        if parts.isEmpty {
            return "Week 1"
        }
        return parts.joined(separator: " · ")
    }

    /// Convenience for Progression detail models already loaded for the hub.
    public static func string(
        from model: ProgressionDetailModel,
        weeklyRateKg: Double? = nil,
        includeBlockLength: Bool = false
    ) -> String {
        let muscle = model.muscles.first
        let mesocyclePhase = muscle?.phaseLabel
            ?? (model.isDeloadWeek ? "Deload" : nil)
        return string(
            currentWeek: muscle?.currentWeek,
            blockLengthWeeks: muscle?.blockLengthWeeks,
            includeBlockLength: includeBlockLength,
            mesocyclePhase: mesocyclePhase,
            experienceLabel: model.experienceLabel,
            goalPhase: model.phaseLabel,
            weeklyRateKg: weeklyRateKg
        )
    }

    /// Maps engine mesocycle labels into journey language (Accumulating → Hypertrophy).
    public static func displayMesocyclePhase(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.lowercased() {
        case "accumulating", "accumulate":
            return "Hypertrophy"
        case "deload":
            return "Deload"
        default:
            return trimmed
        }
    }

    /// First segment of a goal label (`Gain · v-taper` → `Gain`).
    public static func primaryGoalLabel(_ goalPhase: String?) -> String? {
        guard let goalPhase else { return nil }
        let trimmed = goalPhase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let primary = trimmed.split(separator: "·", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let primary, !primary.isEmpty else { return nil }
        return primary
    }

    /// Signed weekly rate copy for cut/gain. Maintain (or missing phase) omits the rate.
    public static func formatWeeklyRate(_ weeklyRateKg: Double, goalPhase: String?) -> String? {
        guard weeklyRateKg.isFinite, weeklyRateKg > 0 else { return nil }
        let phase = (goalPhase ?? "").lowercased()
        let signed: Double
        if phase.hasPrefix("cut") {
            signed = -weeklyRateKg
        } else if phase.hasPrefix("gain") {
            signed = weeklyRateKg
        } else {
            return nil
        }
        let magnitude = String(format: "%.1f", abs(signed))
        let sign = signed < 0 ? "−" : "+"
        return "\(sign)\(magnitude) kg/wk"
    }

    private static func displayTrainingPhase(
        mesocyclePhase: String?,
        experienceLabel: String?
    ) -> String? {
        if let mapped = displayMesocyclePhase(mesocyclePhase) {
            return mapped
        }
        let experience = experienceLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return experience.isEmpty ? nil : experience
    }
}
