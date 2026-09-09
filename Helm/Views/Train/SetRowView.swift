import Core
import DesignSystem
import SwiftUI

struct SetRowView: View {
    let setEntry: SetEntryDraft
    let setNumber: Int
    let exerciseMode: ExerciseMode
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
        switch exerciseMode {
        case .weightReps:
            return (setEntry.mass != nil || previous?.mass != nil)
                && (setEntry.reps != nil || previous?.reps != nil)
        case .bodyweightReps:
            return setEntry.reps != nil || previous?.reps != nil
        case .duration:
            return (setEntry.durationSeconds ?? previous?.durationSeconds ?? 0) > 0
        case .distanceDuration:
            return (setEntry.durationSeconds ?? previous?.durationSeconds ?? 0) > 0
                && (setEntry.distanceKilometers ?? previous?.distanceKilometers ?? 0) > 0
        }
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
        if exerciseMode.isCardio {
            cardioRow
        } else {
            strengthRow
        }
    }

    private var strengthRow: some View {
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

    private var cardioRow: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            HStack(spacing: HelmSpacing.xs) {
                Text("\(setNumber)")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .frame(width: 20)

                cardioField(.durationMinutes, label: "MIN", unit: "")
                if exerciseMode == .distanceDuration {
                    cardioField(.distanceKilometers, label: "KM", unit: "")
                }
                cardioField(.rpe, label: "RPE", unit: "")

                Button(action: onComplete) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            isCompleted ? HelmColor.accent : (isConfirmable ? HelmColor.fg : HelmColor.fgMuted)
                        )
                        .frame(width: HelmLayout.minTapTarget, height: HelmLayout.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCompleted ? "Undo interval" : "Complete interval")
            }

            if let rowValidationMessage {
                Text(rowValidationMessage)
                    .helmType(.body, color: HelmColor.destructive)
            }

            if let previous {
                Button(action: onFillPrevious) {
                    Text("PREV \(cardioPreviousLabel(previous))")
                        .helmType(.monoTag, color: HelmColor.fgSecondary)
                }
                .buttonStyle(.helmPressable)
            }
        }
        .padding(.horizontal, HelmSpacing.xs)
        .padding(.vertical, HelmSpacing.xxs)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.sm)
                .strokeBorder(isCompleted ? HelmColor.accent.opacity(0.6) : HelmColor.hairline, lineWidth: 1)
        }
        .id(setEntry.id)
    }

    private func cardioField(_ field: NumpadFieldKind, label: String, unit: String) -> some View {
        Button {
            onOpenField(field)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text(fieldDisplayText(setEntry, field).isEmpty ? "-" : fieldDisplayText(setEntry, field))
                    .helmType(.number, color: HelmColor.fg)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: HelmLayout.minTapTarget)
            .background(
                activeField?.setID == setEntry.id && activeField?.field == field
                    ? HelmColor.accent.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(fieldDisplayText(setEntry, field).isEmpty ? "empty" : fieldDisplayText(setEntry, field)) \(unit)")
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
        case .durationMinutes: setEntry.durationSeconds != nil
        case .distanceKilometers: setEntry.distanceKilometers != nil
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
        case .durationMinutes:
            guard let seconds = previous?.durationSeconds else { return "-" }
            return seconds.isMultiple(of: 60)
                ? "\(seconds / 60)"
                : String(format: "%.1f", Double(seconds) / 60)
        case .distanceKilometers:
            guard let distance = previous?.distanceKilometers else { return "-" }
            return String(format: "%.2f", distance)
        case .rpe:
            return "-"
        }
    }

    private var activeSetRowField: SetRowField? {
        guard let activeField, activeField.setID == setEntry.id else { return nil }
        switch activeField.field {
        case .weight: return .weight
        case .reps: return .reps
        case .durationMinutes, .distanceKilometers: return nil
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

    private func cardioPreviousLabel(_ previous: PreviousPerformance) -> String {
        var parts: [String] = []
        if let seconds = previous.durationSeconds {
            parts.append(seconds.isMultiple(of: 60) ? "\(seconds / 60) min" : "\(seconds) sec")
        }
        if let distance = previous.distanceKilometers {
            let value = distance.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", distance)
                : String(format: "%.2f", distance)
            parts.append("\(value) km")
        }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
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
        exerciseMode: .weightReps,
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
            case .durationMinutes: set.durationSeconds.map { String($0 / 60) } ?? ""
            case .distanceKilometers: set.distanceKilometers.map { String(format: "%.2f", $0) } ?? ""
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
