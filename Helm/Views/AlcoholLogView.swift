import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct AlcoholLogView: View {
    @Bindable var controller: ManualFoodLogController

    @State private var preset: AlcoholDrinkPreset = .beer
    @State private var quantity = 1
    @State private var bucket: MealBucket

    init(controller: ManualFoodLogController) {
        self.controller = controller
        _bucket = State(initialValue: controller.preferredBucket)
    }

    private var macros: FoodPortionMacros {
        preset.macros(quantity: quantity)
    }

    var body: some View {
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
    }

    private var bucketPicker: some View {
        MealBucketPicker(selection: $bucket, labelStyle: .muted)
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
    NavigationStack {
        AlcoholLogView(controller: ManualFoodLogController.previewController(online: true))
    }
    .helmTheme()
}
