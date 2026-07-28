import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct QuickAddFoodView: View {
    @Bindable var controller: ManualFoodLogController

    @State private var kilocaloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var label = ""
    @State private var bucket: MealBucket
    @FocusState private var kilocaloriesFocused: Bool

    init(controller: ManualFoodLogController) {
        self.controller = controller
        _bucket = State(initialValue: controller.preferredBucket)
    }

    private var macros: FoodPortionMacros? {
        guard let kilocalories = parsedDouble(kilocaloriesText), kilocalories > 0 else { return nil }
        return FoodPortionMacros(
            energyKcal: kilocalories,
            proteinG: parsedDouble(proteinText) ?? 0,
            carbsG: parsedDouble(carbsText) ?? 0,
            fatG: parsedDouble(fatText) ?? 0
        )
    }

    private var isValid: Bool {
        macros != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                Text("Log calories and optional macros.")
                    .helmType(.body, color: HelmColor.fgMuted)

                bucketPicker

                macroField(title: "Calories", text: $kilocaloriesText, unit: "kcal")
                    .focused($kilocaloriesFocused)

                macroField(title: "Protein", text: $proteinText, unit: "g")
                macroField(title: "Carbohydrates", text: $carbsText, unit: "g")
                macroField(title: "Fat", text: $fatText, unit: "g")

                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text("Label (optional)")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                    TextField("e.g. Protein shake", text: $label)
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
            ToolbarItem(placement: .confirmationAction) {
                if controller.isBusy {
                    ProgressView()
                } else {
                    Button("Add") {
                        guard let macros else { return }
                        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await controller.logQuickAdd(
                                macros: macros,
                                label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                                bucket: bucket
                            )
                        }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .onAppear {
            kilocaloriesFocused = true
        }
    }

    private var bucketPicker: some View {
        MealBucketPicker(selection: $bucket, labelStyle: .muted)
    }

    private func macroField(title: String, text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text(title)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            HStack(spacing: HelmSpacing.sm) {
                TextField(unit, text: text)
                    .keyboardType(.decimalPad)
                    .helmType(.number)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                Text(unit)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
    }

    private func parsedDouble(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

#Preview("Quick add") {
    NavigationStack {
        QuickAddFoodView(controller: ManualFoodLogController.previewController(online: true))
    }
    .helmTheme()
}
