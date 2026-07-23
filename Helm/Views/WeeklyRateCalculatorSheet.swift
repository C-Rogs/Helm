import Core
import DesignSystem
import SwiftUI

struct WeeklyRateCalculatorSheet: View {
    let initialPhase: TrainingPhase
    let onApply: (Double, TrainingPhase) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentWeightText = ""
    @State private var targetWeightText = ""
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now
    @State private var result: WeeklyRateCalculator.Result?

    var body: some View {
        NavigationStack {
            Form {
                Section("Current") {
                    TextField("Current weight (kg)", text: $currentWeightText)
                        .keyboardType(.decimalPad)
                }

                Section("Target") {
                    TextField("Target weight (kg)", text: $targetWeightText)
                        .keyboardType(.decimalPad)
                    DatePicker("Target date", selection: $targetDate, in: Date()..., displayedComponents: .date)
                }

                if let result {
                    Section("Suggested") {
                        LabeledContent("Weekly rate") {
                            Text(String(format: "%.2f kg", result.weeklyRateKg))
                        }
                        LabeledContent("Phase") {
                            Text(result.phase.label)
                        }
                        Text(WeeklyRateCalculator.safeRangeHint(for: result.phase))
                            .font(HelmTypography.caption)
                            .foregroundStyle(HelmColor.fgSecondary)
                    }
                }
            }
            .navigationTitle("Rate calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard let result else { return }
                        onApply(result.weeklyRateKg, result.phase)
                        dismiss()
                    }
                    .disabled(result == nil)
                }
            }
            .onChange(of: currentWeightText) { _, _ in recompute() }
            .onChange(of: targetWeightText) { _, _ in recompute() }
            .onChange(of: targetDate) { _, _ in recompute() }
            .onAppear { recompute() }
        }
    }

    private func recompute() {
        guard let current = Double(currentWeightText),
              let target = Double(targetWeightText) else {
            result = nil
            return
        }
        result = WeeklyRateCalculator.calculate(
            WeeklyRateCalculator.Input(
                currentWeightKg: current,
                targetWeightKg: target,
                targetDate: targetDate,
                referenceDate: Date()
            )
        )
    }
}

private extension TrainingPhase {
    var label: String {
        switch self {
        case .cut: "Cut"
        case .maintain: "Maintain"
        case .gain: "Gain"
        }
    }
}
