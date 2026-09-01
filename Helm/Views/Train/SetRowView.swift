import Core
import DesignSystem
import SwiftUI

struct SetRowView: View {
    let setEntry: SetEntryDraft
    let setNumber: Int
    let previous: PreviousPerformance?
    let activeField: NumpadTarget?
    let numpadSelectAll: Bool
    let validationMessage: String?
    let advisoryMessage: String?
    let shakeToken: Int
    let badgeText: String?
    let encouragementGlyph: EncouragementGlyph?
    let showsPRCelebration: Bool
    let fieldDisplayText: (SetEntryDraft, NumpadFieldKind) -> String
    let sessionExerciseID: String
    let onOpenField: (NumpadFieldKind) -> Void
    let onFillPrevious: () -> Void
    let onCycleSetType: () -> Void
    let onComplete: () -> Void

    @Bindable private var focusModePreferences = FocusModePreferences.shared
    @Environment(\.helmReduceMotion) private var reduceMotion

    private var isCompleted: Bool { setEntry.status == .completed }

    /// One tap on the checkmark logs the row: controller falls back to previous
    /// performance for any missing weight/reps, so the row is confirmable when
    /// each is resolvable from stored input or history. RPE stays optional.
    private var isConfirmable: Bool {
        guard !isCompleted else { return false }
        let weightResolvable = setEntry.mass != nil || previous?.mass != nil
        let repsResolvable = setEntry.reps != nil || previous?.reps != nil
        return weightResolvable && repsResolvable
    }

    private var isRowFocused: Bool {
        activeField?.setID == setEntry.id
    }

    private var isSpotlightActive: Bool {
        focusModePreferences.isFocusModeEnabled && activeField != nil
    }

    private var rowValidationMessage: String? {
        if let activeField, activeField.setID == setEntry.id {
            return validationMessage ?? advisoryMessage
        }
        return advisoryMessage
    }

    private var rowShakeToken: Int {
        guard let activeField, activeField.setID == setEntry.id else { return 0 }
        return shakeToken
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SetRow(
                setNumber: setNumber,
                setTypeLabel: setEntry.setType.loggerAbbreviation,
                setTypeAccent: setTypeAccent,
                setIndexAccessibilityLabel: setIndexAccessibilityLabel,
                weightState: fieldState(.weight),
                repsState: fieldState(.reps),
                rpeState: fieldState(.rpe),
                previousValue: previous.map(previousLabel),
                isCompleted: isCompleted,
                isConfirmable: isConfirmable,
                activeField: activeSetRowField,
                validationMessage: rowValidationMessage,
                shakeToken: rowShakeToken,
                badgeText: badgeText,
                onPreviousTap: previous == nil ? nil : onFillPrevious,
                onSetIndexTap: onCycleSetType,
                onFieldTap: { field in
                    switch field {
                    case .weight: onOpenField(.weight)
                    case .reps: onOpenField(.reps)
                    case .rpe: onOpenField(.rpe)
                    }
                },
                onComplete: onComplete
            )

            if let encouragementGlyph {
                EncouragementGlyphView(glyph: encouragementGlyph)
                    .offset(x: -8, y: -12)
                    .allowsHitTesting(false)
            }
        }
        .spotlightEffect(
            isFocused: isRowFocused,
            isFocusModeEnabled: isSpotlightActive
        )
        .overlay {
            if showsPRCelebration {
                RoundedRectangle(cornerRadius: HelmRadius.sm)
                    .strokeBorder(HelmColor.accent.opacity(0.8), lineWidth: 2)
                    .scaleEffect(showsPRCelebration ? 1.02 : 1)
                    .animation(
                        HelmMotion.animation(
                            HelmMotion.quickAnimation.repeatCount(2, autoreverses: true),
                            reduceMotion: reduceMotion
                        ),
                        value: showsPRCelebration
                    )
            }
        }
        .id(setEntry.id)
    }

    private func fieldState(_ field: NumpadFieldKind) -> SetRowFieldValueState {
        let isActive = activeField?.setID == setEntry.id && activeField?.field == field
        let displayText = fieldDisplayText(setEntry, field)
        let prefilledText = prefilledText(for: field)
        let hasStoredValue = hasStoredValue(for: field)

        return SetRowFieldValueStateResolver.resolve(
            hasStoredValue: hasStoredValue,
            displayText: displayText,
            prefilledText: prefilledText,
            isCompleted: isCompleted,
            isActive: isActive,
            isSelectAll: isActive && numpadSelectAll
        )
    }

    private func hasStoredValue(for field: NumpadFieldKind) -> Bool {
        switch field {
        case .weight: setEntry.mass != nil
        case .reps: setEntry.reps != nil
        case .rpe: setEntry.rpe != nil
        }
    }

    private func prefilledText(for field: NumpadFieldKind) -> String? {
        switch field {
        case .weight:
            guard let mass = previous?.mass else { return "-" }
            return formatWeight(mass.kilograms)
        case .reps:
            return previous?.reps.map(String.init) ?? "-"
        case .rpe:
            return "-"
        }
    }

    private var activeSetRowField: SetRowField? {
        guard let activeField, activeField.setID == setEntry.id else { return nil }
        switch activeField.field {
        case .weight: return .weight
        case .reps: return .reps
        case .rpe: return .rpe
        }
    }

    private var setTypeAccent: Color? {
        switch setEntry.setType {
        case .warmup: HelmColor.fgSecondary
        case .dropSet: HelmColor.accent
        case .failure: HelmColor.destructive
        default: nil
        }
    }

    private var setIndexAccessibilityLabel: String {
        setEntry.setType.loggerSetTypeAccessibilityLabel(setNumber: setNumber)
    }

    private func previousLabel(_ previous: PreviousPerformance) -> String {
        let weight = previous.mass.map { formatWeight($0.kilograms) } ?? "-"
        let reps = previous.reps.map(String.init) ?? "-"
        return "\(weight)×\(reps)"
    }

    private func formatWeight(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", kilograms)
            : String(format: "%.1f", kilograms)
    }
}

#Preview("Set row") {
    SetRowView(
        setEntry: SetEntryDraft(
            setIndex: 0,
            status: .planned,
            mass: Mass(kilograms: 80),
            reps: 8,
            rpe: 8
        ),
        setNumber: 1,
        previous: nil,
        activeField: nil,
        numpadSelectAll: false,
        validationMessage: nil,
        advisoryMessage: nil,
        shakeToken: 0,
        badgeText: nil,
        encouragementGlyph: nil,
        showsPRCelebration: false,
        fieldDisplayText: { set, field in
            switch field {
            case .weight: set.mass.map { String(format: "%.0f", $0.kilograms) } ?? ""
            case .reps: set.reps.map(String.init) ?? ""
            case .rpe: set.rpe.map { String(format: "%.0f", $0) } ?? ""
            }
        },
        sessionExerciseID: "session-ex-1",
        onOpenField: { _ in },
        onFillPrevious: {},
        onCycleSetType: {},
        onComplete: {}
    )
    .padding()
    .helmTheme()
}
