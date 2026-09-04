import Foundation

public enum FindingCopy {
    public static func headline(for spec: HypothesisSpec, status: FindingStatus, medianDelta: Double?) -> String {
        let exposure = exposurePhrase(spec.exposure)
        let outcome = spec.outcome.field.displayName
        switch status {
        case .priorSeed:
            return "Studies link \(exposure) with \(outcome)"
        case .emerging:
            return "Starting to notice \(exposure) and \(outcome)"
        case .stable, .memoryConfirmed:
            return directedHeadline(exposure: exposure, outcome: outcome, medianDelta: medianDelta)
        case .retired:
            return "\(exposure) no longer tracks \(outcome)"
        }
    }

    public static func body(
        spec: HypothesisSpec,
        status: FindingStatus,
        nExp: Int,
        nCtrl: Int,
        medianDelta: Double?,
        cliffsDelta _: Double?,
        unitHint _: String?
    ) -> String {
        if status == .priorSeed, let prior = spec.prior {
            return prior.educationalCopy
        }
        var parts: [String] = []
        if let medianDelta {
            let formatted = formatDelta(medianDelta, unit: unit(for: spec.outcome.field))
            parts.append("Median shift \(formatted).")
        }
        parts.append("n=\(nExp)/\(nCtrl).")
        switch status {
        case .emerging:
            parts.insert("Association language only. More days will firm this up.", at: 0)
        case .stable, .memoryConfirmed:
            parts.insert("Personal association, not a causal claim.", at: 0)
        case .retired:
            parts.insert("Effect no longer clears the gates.", at: 0)
        case .priorSeed:
            break
        }
        if spec.copyRegisterHint == .softContext {
            parts.append("Short-term fluid and glycogen, not fat change.")
        }
        return parts.joined(separator: " ")
    }

    public static func register(status: FindingStatus, hint: CopyRegister, verdict: ContrastVerdict) -> CopyRegister {
        if verdict == .suppress { return .suppressed }
        if status == .priorSeed { return .educational }
        if verdict == .killNull { return .null }
        if verdict == .killSample { return .sampleTooSmall }
        if hint == .softContext { return .softContext }
        switch status {
        case .priorSeed: return .educational
        case .emerging: return .tentative
        case .stable, .memoryConfirmed: return .confirmed
        case .retired: return .null
        }
    }

    private static func directedHeadline(exposure: String, outcome: String, medianDelta: Double?) -> String {
        guard let medianDelta, abs(medianDelta) >= 1e-9 else {
            return "On \(exposure), \(outcome) tends to shift"
        }
        let direction = medianDelta > 0 ? "higher" : "lower"
        return "On \(exposure), \(outcome) tends to run \(direction)"
    }

    private static func exposurePhrase(_ exposure: ExposureSpec) -> String {
        switch exposure.op {
        case .present:
            return "\(exposure.field.displayName) days"
        case .absent:
            return "days without \(exposure.field.displayName)"
        case .tertileLow:
            return "low \(exposure.field.displayName)"
        case .tertileHigh:
            return "high \(exposure.field.displayName)"
        case .bandEquals:
            return "\(exposure.band ?? exposure.field.displayName) days"
        case .residualPositive:
            return "above-prescription \(exposure.field.displayName)"
        case .residualNonPositive:
            return "at-or-below-prescription \(exposure.field.displayName)"
        }
    }

    private static func unit(for field: DayFeatureField) -> String {
        switch field {
        case .dietEnergyKcal, .energyResidual: "kcal"
        case .dietProteinG: "g"
        case .sleepAsleepMin, .sleepRemMin, .workoutMinutes: "min"
        case .hrvSdnn: "ms"
        case .restingHr: "bpm"
        case .bodyMassKg: "kg"
        case .sessionVolumeKg, .volumeResidual: "kg"
        default: ""
        }
    }

    private static func formatDelta(_ value: Double, unit: String) -> String {
        let sign = value > 0 ? "+" : ""
        let body = String(format: "%.2f", value)
        if unit.isEmpty { return "\(sign)\(body)" }
        return "\(sign)\(body) \(unit)"
    }
}
