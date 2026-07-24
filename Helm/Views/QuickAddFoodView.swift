import Core
import DesignSystem
import SwiftUI

struct QuickAddFoodView: View {
    @Bindable var controller: ManualFoodLogController
    @Environment(\.dismiss) private var dismiss

    @State private var kilocaloriesText = ""
    @State private var label = ""
    @State private var bucket: MealBucket = .snacks
    @FocusState private var kilocaloriesFocused: Bool

    private var kilocalories: Double? {
        Double(kilocaloriesText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isValid: Bool {
        guard let kilocalories else { return false }
        return kilocalories > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    Text("Log calories without macros. They count toward your TDEE trend.")
                        .helmType(.body, color: HelmColor.fgMuted)

                    bucketPicker

                    VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                        Text("Calories")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                        TextField("kcal", text: $kilocaloriesText)
                            .keyboardType(.decimalPad)
                            .focused($kilocaloriesFocused)
                            .helmType(.number)
                            .padding(HelmSpacing.sm)
                            .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                    }

                    VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                        Text("Label (optional)")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                        TextField("e.g. Beer", text: $label)
                            .helmType(.body)
                            .padding(HelmSpacing.sm)
                            .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                    }
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.cancel()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Log calories") {
                    guard let kilocalories else { return }
                    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await controller.logQuickAdd(
                            kilocalories: kilocalories,
                            label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                            bucket: bucket
                        )
                    }
                }
                .buttonStyle(.helmPrimary)
                .disabled(!isValid || controller.isBusy)
                .padding(HelmSpacing.md)
                .background(HelmColor.surface.opacity(0.96))
            }
            .onAppear {
                kilocaloriesFocused = true
            }
            .onChange(of: controller.phase) { _, newPhase in
                if case .idle = newPhase {
                    dismiss()
                }
            }
        }
    }

    private var bucketPicker: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Meal")
                .helmType(.monoTag, color: HelmColor.fgMuted)
            Picker("Meal", selection: $bucket) {
                ForEach(MealBucket.allCases, id: \.self) { mealBucket in
                    Text(mealBucket.displayName).tag(mealBucket)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

#Preview("Quick add") {
    QuickAddFoodView(controller: ManualFoodLogController.previewController(online: true))
        .helmTheme()
}
