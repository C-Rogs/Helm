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
        SetRow(
            setNumber: setNumber,
            weight: weightText,
            weightPlaceholder: previousWeightPlaceholder,
            reps: repsText,
            repsPlaceholder: previousRepsPlaceholder,
            rpe: rpeText,
            rpePlaceholder: "-",
            previousValue: previous.map(previousLabel),
            isCompleted: isCompleted,
            activeField: activeSetRowField,
            onPreviousTap: previous == nil ? nil : onFillPrevious,
            onFieldTap: { field in
                switch field {
                case .weight: onOpenField(.weight)
                case .reps: onOpenField(.reps)
                case .rpe: onOpenField(.rpe)
                }
            },
            onComplete: onComplete
        )
    }

    private var activeSetRowField: SetRowField? {
        guard let activeField, activeField.setID == setEntry.id else { return nil }
        switch activeField.field {
        case .weight: return .weight
        case .reps: return .reps
        case .rpe: return .rpe
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
