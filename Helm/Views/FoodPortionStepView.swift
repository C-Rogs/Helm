import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct FoodPortionStepView: View {
    let product: ResolvedFoodProduct
    let defaults: FoodPortionDefaults
    let isSaving: Bool
    let onLog: (Double, String?, MealBucket) -> Void
    let onCancel: () -> Void

    @State private var gramsText: String
    @State private var servingLabel: String
    @State private var bucket: MealBucket
    @FocusState private var gramsFocused: Bool

    init(
        product: ResolvedFoodProduct,
        defaults: FoodPortionDefaults,
        isSaving: Bool,
        onLog: @escaping (Double, String?, MealBucket) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.product = product
        self.defaults = defaults
        self.isSaving = isSaving
        self.onLog = onLog
        self.onCancel = onCancel
        _gramsText = State(initialValue: Self.format(defaults.grams))
        _servingLabel = State(initialValue: defaults.servingLabel ?? "")
        _bucket = State(initialValue: MealBucket.snacks)
    }

    private var grams: Double? {
        Double(gramsText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var macros: FoodPortionMacros? {
        guard let grams, grams > 0 else { return nil }
        return product.macros(forGrams: grams)
    }

    private var isValid: Bool {
        macros != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text(product.ref.displayName)
                        .helmType(.title)
                    Text(sourceLabel)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }

                bucketPicker

                if defaults.prefersServingLabel {
                    servingSection
                }

                gramsSection

                if let macros {
                    macroSummary(macros)
                }
            }
            .padding(HelmSpacing.md)
        }
        .helmScreenBackground()
        .navigationTitle("Portion")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", action: onCancel)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Log food") {
                guard let grams, let macros else { return }
                let trimmedServing = servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = defaults.prefersServingLabel && !trimmedServing.isEmpty ? trimmedServing : nil
                _ = macros
                onLog(grams, label, bucket)
            }
            .buttonStyle(.helmPrimary)
            .disabled(!isValid || isSaving)
            .padding(HelmSpacing.md)
            .background(HelmColor.surface.opacity(0.96))
        }
    }

    private var sourceLabel: String {
        switch product.ref.origin {
        case .openFoodFacts:
            "Packaged · per 100 g"
        case .cofid:
            "Produce · per 100 g"
        case .custom:
            "Custom · per 100 g"
        }
    }

    private var bucketPicker: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Meal")
                .helmType(.label)
            Picker("Meal", selection: $bucket) {
                ForEach(MealBucket.allCases, id: \.self) { mealBucket in
                    Text(mealBucket.displayName).tag(mealBucket)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var servingSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text("Serving")
                .helmType(.label)
            TextField("e.g. 1 bar", text: $servingLabel)
                .textInputAutocapitalization(.words)
                .helmType(.body)
                .padding(HelmSpacing.sm)
                .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
    }

    private var gramsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(defaults.prefersServingLabel ? "Grams" : "Portion (grams)")
                .helmType(.label)
            TextField("Grams", text: $gramsText)
                .focused($gramsFocused)
                .keyboardType(.decimalPad)
                .helmType(.body)
                .padding(HelmSpacing.sm)
                .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
    }

    private func macroSummary(_ macros: FoodPortionMacros) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Totals")
                .helmType(.label)
            macroRow("Calories", value: macros.energyKcal, unit: "kcal")
            macroRow("Protein", value: macros.proteinG, unit: "g")
            macroRow("Carbohydrates", value: macros.carbsG, unit: "g")
            macroRow("Fat", value: macros.fatG, unit: "g")
        }
    }

    private func macroRow(_ label: String, value: Double, unit: String) -> some View {
        HStack {
            Text(label)
                .helmType(.body)
            Spacer()
            Text("\(Self.format(value)) \(unit)")
                .helmType(.body, color: HelmColor.fgMuted)
        }
        .padding(HelmSpacing.sm)
        .background(HelmColor.gaugeTrack.opacity(0.2), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

#Preview("Portion packaged") {
    NavigationStack {
        FoodPortionStepView(
            product: ResolvedFoodProduct(
                ref: FoodProductRef(
                    origin: .openFoodFacts,
                    externalID: "5050159001234",
                    displayName: "Grenade Carb Killa"
                ),
                per100gKcal: 380,
                per100gProteinG: 35,
                per100gCarbsG: 18,
                per100gFatG: 12,
                confidence: .branded,
                suggestedGrams: 60,
                servingLabel: "1 bar",
                source: .openFoodFacts
            ),
            defaults: FoodPortionDefaults(grams: 60, servingLabel: "1 bar", prefersServingLabel: true),
            isSaving: false,
            onLog: { _, _, _ in },
            onCancel: {}
        )
    }
    .helmTheme()
}

#Preview("Portion produce") {
    NavigationStack {
        FoodPortionStepView(
            product: ResolvedFoodProduct(
                ref: FoodProductRef(origin: .cofid, externalID: "13-145", displayName: "Banana, flesh only"),
                per100gKcal: 89,
                per100gProteinG: 1.1,
                per100gCarbsG: 20.3,
                per100gFatG: 0.3,
                confidence: .exact,
                source: .cofid
            ),
            defaults: FoodPortionDefaults(grams: 100, servingLabel: nil, prefersServingLabel: false),
            isSaving: false,
            onLog: { _, _, _ in },
            onCancel: {}
        )
    }
    .helmTheme()
}
