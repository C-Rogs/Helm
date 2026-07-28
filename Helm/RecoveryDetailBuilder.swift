import Core
import DesignSystem
import Foundation
import HealthKitIngest
import Persistence
import ReadinessKit

enum RecoveryDetailBuilder {
    struct BuildContext {
        let score: ReadinessScore
        let displayRestingHeartRate: Int?
        let baseline: ReadinessBaselineState?
        let sleepHours: Double?
        let history: [ReadinessHistoryPoint]
        let briefNarration: String?
        let briefIsEngineOnly: Bool
        let coachAvailable: Bool
    }

    static func build(context: BuildContext) -> RecoveryDetailModel {
        let score = context.score
        let helmState = HelmState.readiness(score: Double(score.score))
        let targetBand = arcTargetBand(for: score.band)
        let narration = recoveryNarration(
            score: score,
            briefNarration: context.briefNarration,
            briefIsEngineOnly: context.briefIsEngineOnly,
            coachAvailable: context.coachAvailable
        )

        let contributors = [
            hrvContributor(score: score, baseline: context.baseline?.hrvChronic),
            restingHRContributor(
                score: score,
                displayValue: context.displayRestingHeartRate,
                baseline: context.baseline?.restingHR
            ),
            sleepContributor(
                hours: context.sleepHours,
                zScore: score.contributors.zSleep,
                baseline: context.baseline?.sleepDuration
            )
        ]

        let historyPoints = context.history.map { point in
            RecoveryHistoryPoint(
                dayLabel: dayLabel(for: point.helmDay),
                score: point.score,
                state: point.state
            )
        }

        return RecoveryDetailModel(
            score: score.score,
            helmState: helmState,
            targetBand: targetBand,
            narration: narration,
            isEngineOnly: !context.coachAvailable || context.briefIsEngineOnly,
            citationLabel: context.coachAvailable && !context.briefIsEngineOnly ? "ev-readiness-arc" : nil,
            contributors: contributors,
            history: historyPoints,
            validNights: score.validNights,
            coachPrompt: "Why is my ARC score \(score.score) today?",
            isCoachHandoffEnabled: context.coachAvailable
        )
    }

    static func load(
        store: PersistenceStore,
        score: ReadinessScore,
        briefNarration: String?,
        briefIsEngineOnly: Bool,
        coachAvailable: Bool,
        calendar: Calendar = .current
    ) throws -> (model: RecoveryDetailModel, history: [ReadinessHistoryPoint]) {
        let today = HelmDay.day(for: .now, calendar: calendar)
        let baseline = try loadBaseline(from: store)
        let sleepHours = try store.sleep.totalSleepHours(for: today, calendar: calendar)
        let todayMetrics = try store.dailyMetrics.fetch(helmDay: today)
        let yesterdayMetrics = try store.dailyMetrics.fetch(
            helmDay: today.adding(days: -1, calendar: calendar)
        )
        let displayRestingHeartRate = score.restingHeartRate
            ?? todayMetrics?.restingHeartRate
            ?? yesterdayMetrics?.restingHeartRate
        let (history, _) = try TrendsDataBuilder.buildReadinessPage(
            store: store,
            endingAt: today,
            offset: 0
        )

        let model = build(
            context: BuildContext(
                score: score,
                displayRestingHeartRate: displayRestingHeartRate,
                baseline: baseline,
                sleepHours: sleepHours,
                history: history,
                briefNarration: briefNarration,
                briefIsEngineOnly: briefIsEngineOnly,
                coachAvailable: coachAvailable
            )
        )
        return (model, history)
    }

    private static func loadBaseline(from store: PersistenceStore) throws -> ReadinessBaselineState? {
        guard let json = try store.readiness.fetchBaselineJSON(),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ReadinessBaselineState.self, from: data)
    }

    private static func arcTargetBand(for band: ReadinessBand) -> ClosedRange<Double> {
        switch band {
        case .depleted: 0 ... 33
        case .balanced: 34 ... 66
        case .primed: 67 ... 100
        }
    }

    private static func recoveryNarration(
        score: ReadinessScore,
        briefNarration: String?,
        briefIsEngineOnly: Bool,
        coachAvailable: Bool
    ) -> String {
        if coachAvailable,
           !briefIsEngineOnly,
           let briefNarration,
           let readinessSentence = readinessSentence(from: briefNarration) {
            return readinessSentence
        }
        return engineSummary(for: score)
    }

    private static func readinessSentence(from narration: String) -> String? {
        let trimmed = narration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = trimmed.range(of: ".") {
            let sentence = String(trimmed[..<range.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? trimmed : sentence
        }
        return trimmed
    }

    private static func engineSummary(for score: ReadinessScore) -> String {
        switch score.confidence {
        case .high:
            return "\(score.band.rawValue.capitalized) recovery with \(score.validNights) baseline nights."
        case .medium:
            return "Provisional score with \(score.validNights)/14 baseline nights."
        case .low:
            return "Low confidence while the baseline is still forming."
        }
    }

    private static func hrvContributor(
        score: ReadinessScore,
        baseline: ReadinessBaseline?
    ) -> RecoveryContributorRow {
        let value = score.effectiveHRVMilliseconds ?? 0
        let band = personalBand(baseline)
        let state = contributorState(zScore: score.contributors.zHRV)
        return RecoveryContributorRow(
            id: "hrv",
            label: "HRV",
            value: value,
            band: band,
            unit: "ms",
            state: state,
            verdictTag: verdictTag(zScore: score.contributors.zHRV, higherIsBetter: true)
        )
    }

    private static func restingHRContributor(
        score: ReadinessScore,
        displayValue: Int?,
        baseline: ReadinessBaseline?
    ) -> RecoveryContributorRow {
        let hasValue = displayValue != nil
        let value = Double(displayValue ?? 0)
        let band = personalBand(baseline)
        let state = contributorState(zScore: score.contributors.zRestingHR)
        return RecoveryContributorRow(
            id: "rhr",
            label: "Resting HR",
            value: value,
            band: band,
            unit: "bpm",
            state: state,
            verdictTag: hasValue
                ? verdictTag(zScore: score.contributors.zRestingHR, higherIsBetter: false)
                : "N/A",
            decimalPlaces: 0,
            isValueAvailable: hasValue
        )
    }

    private static func sleepContributor(
        hours: Double?,
        zScore: Double?,
        baseline: ReadinessBaseline?
    ) -> RecoveryContributorRow {
        let hasValue = hours != nil
        let value = hours ?? 0
        let band = personalBand(baseline)
        let state = contributorState(zScore: zScore)
        let tag = band == nil ? "PROVISIONAL" : verdictTag(zScore: zScore, higherIsBetter: true)
        return RecoveryContributorRow(
            id: "sleep",
            label: "Sleep",
            value: value,
            band: band,
            unit: "h",
            state: state,
            verdictTag: tag,
            isValueAvailable: hasValue
        )
    }

    private static func personalBand(_ baseline: ReadinessBaseline?) -> ClosedRange<Double>? {
        guard let baseline else { return nil }
        let lower = baseline.mean - baseline.robustSigma
        let upper = baseline.mean + baseline.robustSigma
        guard upper > lower else { return nil }
        return lower ... upper
    }

    private static func contributorState(zScore: Double?) -> HelmState {
        guard let zScore else { return .compromised }
        if zScore > 0.75 { return .primed }
        if zScore < -0.75 { return .depleted }
        return .ready
    }

    private static func verdictTag(zScore: Double?, higherIsBetter: Bool) -> String? {
        guard let zScore else { return nil }
        if higherIsBetter {
            if zScore > 0.75 { return "GOOD" }
            if zScore < -0.75 { return "LOW" }
            return "TYPICAL"
        }
        if zScore > 0.75 { return "GOOD" }
        if zScore < -0.75 { return "HIGH" }
        return "TYPICAL"
    }

    private static func dayLabel(for helmDay: HelmDay) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        let components = helmDay.dateComponents()
        guard let date = Calendar.current.date(from: components) else {
            return "\(helmDay.month)/\(helmDay.day)"
        }
        return formatter.string(from: date)
    }
}
