import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct AlcoholLogView: View {
    @Bindable var controller: ManualFoodLogController

    @State private var preset: AlcoholDrinkPreset = .beerPint
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

                drinkPicker

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
            ToolbarItem(placement: .confirmationAction) {
                if controller.isBusy {
                    ProgressView()
                } else {
                    Button("Add") {
                        Task {
                            await controller.logAlcohol(
                                preset: preset,
                                quantity: quantity,
                                bucket: bucket
                            )
                        }
                    }
                }
            }
        }
    }

    private var drinkPicker: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Drink")
                .helmType(.monoTag, color: HelmColor.fgMuted)

            ForEach(AlcoholDrinkPreset.Category.allCases, id: \.self) { category in
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text(category.title)
                        .helmType(.label, color: HelmColor.fgSecondary)

                    ForEach(category.presets, id: \.self) { drink in
                        Button {
                            HapticEngine.shared.play(.selection)
                            preset = drink
                        } label: {
                            HStack {
                                Text(drink.displayName)
                                    .helmType(.body)
                                Spacer()
                                Text("\(Int(drink.kilocaloriesPerServing)) kcal")
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                                if preset == drink {
                                    HelmIconView(.checkmark, context: .inline)
                                        .foregroundStyle(HelmColor.accent)
                                }
                            }
                            .padding(HelmSpacing.sm)
                            .background(
                                preset == drink
                                    ? HelmColor.accent.opacity(0.12)
                                    : HelmColor.gaugeTrack.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
            Text(quantity == 1 ? preset.servingLabel : "\(quantity) × \(preset.servingLabel)")
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
