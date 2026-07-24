import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct AlcoholLogView: View {
    @Bindable var controller: ManualFoodLogController
    @Environment(\.dismiss) private var dismiss

    @State private var preset: AlcoholDrinkPreset = .beer
    @State private var quantity = 1
    @State private var bucket: MealBucket = .snacks

    private var macros: FoodPortionMacros {
        preset.macros(quantity: quantity)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    Text("Explicit alcohol kcal counts toward TDEE. Macro gap covers any untracked remainder.")
                        .helmType(.body, color: HelmColor.fgMuted)

                    bucketPicker

                    VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                        Text("Drink")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                        Picker("Drink", selection: $preset) {
                            ForEach(AlcoholDrinkPreset.allCases, id: \.self) { drink in
                                Text(drink.displayName).tag(drink)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Stepper(value: $quantity, in: 1 ... 12) {
                        HStack {
                            Text("Quantity")
                                .helmType(.body)
                            Spacer()
                            Text("\(quantity)")
                                .helmType(.number)
                        }
                    }

                    macroSummary
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Alcohol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.cancel()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Log alcohol") {
                    Task {
                        await controller.logAlcohol(
                            preset: preset,
                            quantity: quantity,
                            bucket: bucket
                        )
                    }
                }
                .buttonStyle(.helmPrimary)
                .disabled(controller.isBusy)
                .padding(HelmSpacing.md)
                .background(HelmColor.surface.opacity(0.96))
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

    private var macroSummary: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Estimate")
                .helmType(.monoTag, color: HelmColor.fgMuted)
            HStack(alignment: .firstTextBaseline) {
                HelmNumericText(Int(macros.energyKcal.rounded()))
                    .helmType(.bigNumber)
                Text("kcal")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
            Text(preset.servingLabel)
                .helmType(.body, color: HelmColor.fgMuted)
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }
}

#Preview("Alcohol log") {
    AlcoholLogView(controller: ManualFoodLogController.previewController(online: true))
        .helmTheme()
}
