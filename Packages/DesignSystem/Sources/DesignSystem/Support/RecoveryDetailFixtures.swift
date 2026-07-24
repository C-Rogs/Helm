import Foundation

public extension RecoveryDetailModel {
    static let goodFixture = RecoveryDetailModel(
        score: 72,
        helmState: .primed,
        targetBand: 67 ... 100,
        narration: "ARC 72, primed, high confidence. Today's session: 16 sets across 5 exercises (gain).",
        isEngineOnly: false,
        citationLabel: "ev-readiness-arc",
        contributors: [
            RecoveryContributorRow(
                id: "hrv",
                label: "HRV",
                value: 48.2,
                band: 44.3 ... 49.3,
                unit: "ms",
                state: .ready,
                verdictTag: "GOOD"
            ),
            RecoveryContributorRow(
                id: "rhr",
                label: "Resting HR",
                value: 51,
                band: 48 ... 54,
                unit: "bpm",
                state: .ready,
                verdictTag: "GOOD",
                decimalPlaces: 0
            ),
            RecoveryContributorRow(
                id: "sleep",
                label: "Sleep",
                value: 7.4,
                band: 6.8 ... 7.6,
                unit: "h",
                state: .ready,
                verdictTag: "GOOD"
            )
        ],
        history: [
            RecoveryHistoryPoint(dayLabel: "Jul 10", score: 55, state: .ready),
            RecoveryHistoryPoint(dayLabel: "Jul 17", score: 68, state: .ready),
            RecoveryHistoryPoint(dayLabel: "Jul 23", score: 72, state: .primed)
        ],
        validNights: 18,
        coachPrompt: "Why is my ARC score 72 today?",
        isCoachHandoffEnabled: true
    )

    static let compromisedFixture = RecoveryDetailModel(
        score: 41,
        helmState: .compromised,
        targetBand: 34 ... 66,
        narration: "Balanced recovery with 16 baseline nights.",
        isEngineOnly: true,
        citationLabel: nil,
        contributors: [
            RecoveryContributorRow(
                id: "hrv",
                label: "HRV",
                value: 38.5,
                band: 44.3 ... 49.3,
                unit: "ms",
                state: .depleted,
                verdictTag: "LOW"
            ),
            RecoveryContributorRow(
                id: "rhr",
                label: "Resting HR",
                value: 58,
                band: 48 ... 54,
                unit: "bpm",
                state: .compromised,
                verdictTag: "HIGH",
                decimalPlaces: 0
            ),
            RecoveryContributorRow(
                id: "sleep",
                label: "Sleep",
                value: 5.9,
                band: 6.8 ... 7.6,
                unit: "h",
                state: .depleted,
                verdictTag: "LOW"
            )
        ],
        history: [
            RecoveryHistoryPoint(dayLabel: "Jul 10", score: 62, state: .ready),
            RecoveryHistoryPoint(dayLabel: "Jul 17", score: 48, state: .compromised),
            RecoveryHistoryPoint(dayLabel: "Jul 23", score: 41, state: .compromised)
        ],
        validNights: 16,
        coachPrompt: "Why is my ARC score 41 today?",
        isCoachHandoffEnabled: true
    )

    static let coldStartFixture = RecoveryDetailModel(
        score: 58,
        helmState: .ready,
        targetBand: 34 ... 66,
        narration: "Provisional score with 6/14 baseline nights.",
        isEngineOnly: true,
        citationLabel: nil,
        contributors: [
            RecoveryContributorRow(
                id: "hrv",
                label: "HRV",
                value: 42.1,
                band: nil,
                unit: "ms",
                state: .ready,
                verdictTag: "PROVISIONAL"
            ),
            RecoveryContributorRow(
                id: "rhr",
                label: "Resting HR",
                value: 54,
                band: nil,
                unit: "bpm",
                state: .ready,
                verdictTag: "PROVISIONAL",
                decimalPlaces: 0
            ),
            RecoveryContributorRow(
                id: "sleep",
                label: "Sleep",
                value: 6.8,
                band: nil,
                unit: "h",
                state: .ready,
                verdictTag: "PROVISIONAL"
            )
        ],
        history: [
            RecoveryHistoryPoint(dayLabel: "Jul 20", score: 52, state: .ready),
            RecoveryHistoryPoint(dayLabel: "Jul 23", score: 58, state: .ready)
        ],
        validNights: 6,
        coachPrompt: "Why is my ARC score 58 today?",
        isCoachHandoffEnabled: true
    )

    static let offlineFixture: RecoveryDetailModel = {
        var model = goodFixture
        return RecoveryDetailModel(
            score: model.score,
            helmState: model.helmState,
            targetBand: model.targetBand,
            narration: "Balanced recovery with 18 baseline nights.",
            isEngineOnly: true,
            citationLabel: nil,
            contributors: model.contributors,
            history: model.history,
            validNights: model.validNights,
            coachPrompt: model.coachPrompt,
            isCoachHandoffEnabled: false
        )
    }()
}
