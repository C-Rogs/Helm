import Core
import DesignSystem
import SwiftUI

/// Single exercise + current set card for focus mode logging.
/// Shows the exercise image, set info, coaching cue, weight/reps/RPE fields,
/// and a big "Log Set" button.
struct FocusExerciseCard: View {
    let exercise: WorkoutSessionExerciseDraft
    let displayName: String
    let coachingCue: String?
    let imageURL: URL?
    let currentSetIndex: Int
    let previous: PreviousPerformance?
    let activeField: NumpadTarget?
    let numpadSelectAll: Bool
    let showsPRCelebration: Bool
    let encouragementGlyph: EncouragementGlyph?
    let fieldDisplayText: (SetEntryDraft, NumpadFieldKind) -> String
    let onOpenField: (NumpadFieldKind) -> Void
    let onFillPrevious: () -> Void
    let onCycleSetType: () -> Void
    let onCompleteSet: () -> Void

    @Environment(\.helmReduceMotion) private var reduceMotion

    private var currentSet: SetEntryDraft? {
        guard exercise.sets.indices.contains(currentSetIndex) else { return nil }
        return exercise.sets[currentSetIndex]
    }

    private var isCompleted: Bool {
        currentSet?.status == .completed
    }

    private var totalSets: Int {
        exercise.sets.count
    }

    private var setNumber: Int {
        currentSetIndex + 1
    }

    private var setTypeLabel: String {
        currentSet?.setType.loggerAbbreviation
            ?? currentSet?.setType.rawValue.replacingOccurrences(of: "_", with: " ")
            ?? "Working"
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                imageSection
                detailsSection
            }
        }
        .overlay {
            if showsPRCelebration {
                RoundedRectangle(cornerRadius: HelmRadius.md)
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
    }

    // MARK: - Image

    private var imageSection: some View {
        Group {
            if imageURL != nil {
                ExerciseImageView(
                    url: imageURL,
                    fallbackLabel: displayName
                )
                .frame(height: imageHeight)
                .clipped()
            }
            // No image: show nothing here; exercise name lives in setInfoRow instead
        }
    }

    private var imageHeight: CGFloat {
        UIScreen.main.bounds.height * 0.26
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            // Only show name here when there's no image (image has its own fallback label)
            if imageURL == nil {
                Text(displayName)
                    .helmType(.title)
                    .lineLimit(2)
            }
            setInfoRow
            cueAndPrevious
            fieldRow
            logSetButton
        }
        .padding(HelmSpacing.md)
    }

    // MARK: - Set info row

    private var setInfoRow: some View {
        HStack(spacing: HelmSpacing.xs) {
            Text("Set \(setNumber) of \(totalSets)")
                .helmType(.label)

            if let setType = currentSet?.setType, setType != .normal {
                Text("·")
                    .helmType(.monoTag, color: HelmColor.fgMuted)

                Button(action: onCycleSetType) {
                    Text(setTypeLabel)
                        .helmType(.monoTag, color: setTypeColor)
                        .padding(.horizontal, HelmSpacing.xs)
                        .padding(.vertical, 2)
                        .background(setTypeColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.helmPressable)
            }

            Spacer()

            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(HelmColor.accent)
                    .font(.title3)
                    .accessibilityLabel("Set completed")
            } else {
                // Tap anywhere on the row to cycle set type when it's a normal working set
                Button(action: onCycleSetType) {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(HelmColor.fgMuted)
                }
                .buttonStyle(.helmPressable)
                .accessibilityLabel("Change set type")
            }
        }
    }

    private var setTypeColor: Color {
        switch currentSet?.setType {
        case .warmup: HelmColor.fgSecondary
        case .dropSet: HelmColor.accent
        case .failure: HelmColor.destructive
        default: HelmColor.fgSecondary
        }
    }

    // MARK: - Coaching cue + previous

    private var cueAndPrevious: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            if let coachingCue, !coachingCue.isEmpty {
                Text(coachingCue)
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            if let previous {
                previousRow(previous)
            }
        }
    }

    private func previousRow(_ previous: PreviousPerformance) -> some View {
        Button(action: onFillPrevious) {
            HStack(spacing: HelmSpacing.xxs) {
                Text("Previous:")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text(previousLabel(previous))
                    .helmType(.monoTag, color: HelmColor.fgSecondary)
                Text("Tap to fill")
                    .helmType(.monoTag, color: HelmColor.accent)
            }
        }
        .buttonStyle(.helmPressable)
        .accessibilityLabel("Fill from previous: \(previousLabel(previous))")
    }

    private func previousLabel(_ previous: PreviousPerformance) -> String {
        let weight = previous.mass.map { formatWeight($0.kilograms) } ?? "-"
        let reps = previous.reps.map(String.init) ?? "-"
        return "\(weight)kg × \(reps)"
    }

    // MARK: - Field row

    private var fieldRow: some View {
        HStack(spacing: HelmSpacing.sm) {
            fieldButton(.weight, label: "Weight", unit: "kg")
            fieldButton(.reps, label: "Reps", unit: "")
            fieldButton(.rpe, label: "RPE", unit: "")
        }
    }

    private func fieldButton(_ kind: NumpadFieldKind, label: String, unit: String) -> some View {
        Button {
            onOpenField(kind)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                fieldValueText(kind, unit: unit)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.sm)
                    .fill(fieldBackground(kind))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HelmRadius.sm)
                    .stroke(fieldBorder(kind), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(fieldAccessibilityValue(kind))")
    }

    private func fieldValueText(_ kind: NumpadFieldKind, unit: String) -> some View {
        let display = currentSet.map { fieldDisplayText($0, kind) } ?? ""
        let state = fieldState(kind, displayText: display)

        return Group {
            if display.isEmpty {
                Text("-")
                    .helmType(.body, color: HelmColor.fgMuted)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(display)
                        .helmType(.body, color: SetRowFieldValueStateResolver.textColor(for: state))
                    if !unit.isEmpty {
                        Text(unit)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }
            }
        }
    }

    private func fieldState(_ kind: NumpadFieldKind, displayText: String) -> SetRowFieldValueState {
        let isActive = activeField?.setID == currentSet?.id && activeField?.field == kind
        let hasStored: Bool = {
            switch kind {
            case .weight: currentSet?.mass != nil
            case .reps: currentSet?.reps != nil
            case .rpe: currentSet?.rpe != nil
            }
        }()
        let prefilled: String? = {
            switch kind {
            case .weight:
                previous?.mass.map { formatWeight($0.kilograms) }
            case .reps:
                previous?.reps.map(String.init)
            case .rpe:
                nil
            }
        }()

        return SetRowFieldValueStateResolver.resolve(
            hasStoredValue: hasStored,
            displayText: displayText,
            prefilledText: prefilled,
            isCompleted: isCompleted,
            isActive: isActive,
            isSelectAll: isActive && numpadSelectAll
        )
    }

    private func fieldBackground(_ kind: NumpadFieldKind) -> Color {
        let isActive = activeField?.setID == currentSet?.id && activeField?.field == kind
        return isActive ? HelmColor.accent.opacity(0.08) : HelmColor.surfaceElevated
    }

    private func fieldBorder(_ kind: NumpadFieldKind) -> Color {
        let isActive = activeField?.setID == currentSet?.id && activeField?.field == kind
        return isActive ? HelmColor.accent : HelmColor.hairline
    }

    private func fieldAccessibilityValue(_ kind: NumpadFieldKind) -> String {
        currentSet.flatMap { fieldDisplayText($0, kind) } ?? "empty"
    }

    // MARK: - Log Set button

    private var logSetButton: some View {
        Button(action: onCompleteSet) {
            ZStack {
                if let encouragementGlyph {
                    EncouragementGlyphView(glyph: encouragementGlyph)
                        .offset(x: -8, y: -12)
                        .allowsHitTesting(false)
                }

                Text(isCompleted ? "UNDO SET" : "LOG SET")
                    .helmFont(.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HelmSpacing.md)
                    .background(
                        isCompleted
                            ? HelmColor.surfaceElevated
                            : HelmColor.buttonPrimaryBackground,
                        in: RoundedRectangle(cornerRadius: HelmRadius.md)
                    )
                    .foregroundStyle(
                        isCompleted
                            ? HelmColor.fgSecondary
                            : HelmColor.buttonPrimaryForeground
                    )
                    .overlay {
                        if !isCompleted {
                            RoundedRectangle(cornerRadius: HelmRadius.md)
                                .strokeBorder(HelmColor.accent.opacity(0.3), lineWidth: 1)
                        }
                    }
            }
        }
        .buttonStyle(.helmPressable)
        .accessibilityLabel(isCompleted ? "Undo set" : "Log set")
        .accessibilityHint(isCompleted ? "Marks this set as not completed" : "Records this set as completed")
        .padding(.top, HelmSpacing.xs)
    }

    // MARK: - Helpers

    private func formatWeight(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", kilograms)
            : String(format: "%.1f", kilograms)
    }
}

#Preview("Focus card active") {
    FocusExerciseCard(
        exercise: WorkoutSessionExerciseDraft(
            exerciseID: "bench",
            displayOrder: 0,
            exerciseMode: .weightReps,
            targetRestSeconds: 90,
            sets: [
                SetEntryDraft(setIndex: 0, status: .completed, mass: Mass(kilograms: 80), reps: 8, rpe: 7),
                SetEntryDraft(setIndex: 1, status: .completed, mass: Mass(kilograms: 82.5), reps: 8, rpe: 8),
                SetEntryDraft(setIndex: 2, status: .planned, mass: Mass(kilograms: 85), reps: 8, rpe: 8),
            ]
        ),
        displayName: "Bench Press (Barbell)",
        coachingCue: "Drive through your heels and keep your chest proud.",
        imageURL: nil,
        currentSetIndex: 2,
        previous: PreviousPerformance(
            exerciseID: "bench",
            setIndex: 2,
            setType: .normal,
            mass: Mass(kilograms: 80),
            reps: 8,
            completedAt: Date().addingTimeInterval(-604800)
        ),
        activeField: nil,
        numpadSelectAll: false,
        showsPRCelebration: false,
        encouragementGlyph: nil,
        fieldDisplayText: { set, field in
            switch field {
            case .weight: set.mass.map { String(format: "%.0f", $0.kilograms) } ?? ""
            case .reps: set.reps.map(String.init) ?? ""
            case .rpe: set.rpe.map { String(format: "%.0f", $0) } ?? ""
            }
        },
        onOpenField: { _ in },
        onFillPrevious: {},
        onCycleSetType: {},
        onCompleteSet: {}
    )
    .padding()
    .helmTheme()
}