import Core
import DesignSystem
import SwiftUI

struct SetRowView: View {
    let setEntry: SetEntryDraft
    let setNumber: Int
    let previous: PreviousPerformance?
    let activeField: NumpadTarget?
    let sessionExerciseID: String
    let onOpenField: (NumpadFieldKind) -> Void
    let onFillPrevious: () -> Void
    let onComplete: () -> Void

    private var isCompleted: Bool { setEntry.status == .completed }

    var body: some View {
        HStack(spacing: HelmSpacing.xs) {
            Text("\(setNumber)")
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.textSecondary)
                .frame(width: 20, alignment: .leading)

            previousColumn

            SetValueField(
                title: "kg",
                value: weightText,
                placeholder: previousWeightPlaceholder,
                isActive: isFieldActive(.weight),
                action: { onOpenField(.weight) }
            )

            SetValueField(
                title: "reps",
                value: repsText,
                placeholder: previousRepsPlaceholder,
                isActive: isFieldActive(.reps),
                action: { onOpenField(.reps) }
            )

            SetValueField(
                title: "RPE",
                value: rpeText,
                placeholder: "-",
                isActive: isFieldActive(.rpe),
                action: { onOpenField(.rpe) }
            )
            .frame(width: 56)

            Button(action: onComplete) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? HelmColor.positive : HelmColor.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleted ? "Set completed" : "Complete set")
        }
        .opacity(isCompleted ? 0.72 : 1)
    }

    @ViewBuilder
    private var previousColumn: some View {
        if let previous {
            Button(action: onFillPrevious) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("prev")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HelmColor.textTertiary)
                    Text(previousLabel(previous))
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        } else {
            Text("-")
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var weightText: String {
        guard let mass = setEntry.mass else { return "" }
        return formatWeight(mass.kilograms)
    }

    private var repsText: String {
        setEntry.reps.map(String.init) ?? ""
    }

    private var rpeText: String {
        guard let rpe = setEntry.rpe else { return "" }
        return rpe.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rpe)
            : String(format: "%.1f", rpe)
    }

    private var previousWeightPlaceholder: String {
        guard let mass = previous?.mass else { return "-" }
        return formatWeight(mass.kilograms)
    }

    private var previousRepsPlaceholder: String {
        previous?.reps.map(String.init) ?? "-"
    }

    private func isFieldActive(_ field: NumpadFieldKind) -> Bool {
        activeField?.setID == setEntry.id && activeField?.field == field
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
        previous: PreviousPerformance(
            exerciseID: "ex-1",
            setIndex: 0,
            setType: .normal,
            mass: Mass(kilograms: 77.5),
            reps: 8,
            completedAt: Date()
        ),
        activeField: nil,
        sessionExerciseID: "session-ex-1",
        onOpenField: { _ in },
        onFillPrevious: {},
        onComplete: {}
    )
    .padding()
    .helmTheme()
}

#Preview("Set row completed") {
    SetRowView(
        setEntry: SetEntryDraft(
            setIndex: 1,
            status: .completed,
            mass: Mass(kilograms: 80),
            reps: 8,
            completedAt: Date()
        ),
        setNumber: 2,
        previous: nil,
        activeField: nil,
        sessionExerciseID: "session-ex-1",
        onOpenField: { _ in },
        onFillPrevious: {},
        onComplete: {}
    )
    .padding()
    .helmTheme()
}
