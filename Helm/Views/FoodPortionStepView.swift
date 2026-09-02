import Core
import DesignSystem
import HealthKitIngest
import NutritionKit
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.cameronro.helm", category: "FoodPortionAccuracy")

struct FoodPortionStepView: View {
    let product: ResolvedFoodProduct
    let defaults: FoodPortionDefaults
    let isSaving: Bool
    let onLog: (Double, String?, MealBucket) -> Void
    let onCancel: () -> Void

    @State private var servingsText: String
    @State private var selectedServingLabel: String
    @State private var bucket: MealBucket

    private let servingOptions: [ProducePortionOption]

    init(
        product: ResolvedFoodProduct,
        defaults: FoodPortionDefaults,
        isSaving: Bool,
        initialBucket: MealBucket = .snacks,
        onLog: @escaping (Double, String?, MealBucket) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.product = product
        self.defaults = defaults
        self.isSaving = isSaving
        self.onLog = onLog
        self.onCancel = onCancel
        let extras = Self.countableMenuExtras(from: defaults.inputMode)
        let options = PortionOptionCatalog.servingMenu(
            for: product.ref.displayName,
            cofidID: product.ref.origin == .cofid ? product.ref.externalID : nil,
            origin: Self.mapOrigin(product.ref.origin),
            suggestedGrams: product.suggestedGrams ?? defaults.grams,
            servingLabel: product.servingLabel ?? defaults.servingLabel,
            defaultGrams: defaults.grams,
            extra: extras
        )
        servingOptions = options
        let initial = Self.initialServing(
            in: options,
            servingLabel: defaults.servingLabel,
            sizeLabel: defaults.defaultSizeLabel
        )
        _selectedServingLabel = State(initialValue: initial?.label ?? "1 g")
        let unitGrams = initial?.grams ?? 1
        _servingsText = State(
            initialValue: PortionServings.format(
                PortionServings.servings(grams: defaults.grams, unitGrams: unitGrams)
            )
        )
        _bucket = State(initialValue: initialBucket)
    }

    private var selectedServing: ProducePortionOption? {
        servingOptions.first { $0.label == selectedServingLabel } ?? servingOptions.first
    }

    private var grams: Double? {
        guard let servings = PortionServings.parse(servingsText),
              let unitGrams = selectedServing?.grams else { return nil }
        return PortionServings.totalGrams(servings: servings, unitGrams: unitGrams)
    }

    private var macros: FoodPortionMacros? {
        guard let grams, grams > 0 else { return nil }
        return product.macros(forGrams: grams)
    }

    private var isValid: Bool {
        macros != nil
    }

    private var resolvedServingLabel: String? {
        guard let servings = PortionServings.parse(servingsText),
              let size = selectedServing?.label else { return nil }
        return PortionServings.displayLabel(servings: servings, servingSize: size)
    }

    private var portionSummary: String? {
        guard let grams, let macros else { return nil }
        let gramsPart = "\(FoodLogDisplayFormatter.formatNumber(grams)) g"
        let kcalPart = "\(FoodLogDisplayFormatter.formatNumber(macros.energyKcal)) kcal"
        if let label = resolvedServingLabel {
            return "\(label) · \(gramsPart) · \(kcalPart)"
        }
        return "\(gramsPart) · \(kcalPart)"
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

                ServingQuantityFields(
                    options: servingOptions,
                    servingsText: $servingsText,
                    selectedLabel: $selectedServingLabel
                )

                if let portionSummary {
                    Text(portionSummary)
                        .helmType(.body, color: HelmColor.fgSecondary)
                }

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
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let grams else { return }
                    if abs(grams - defaults.grams) > 5 {
                        logger.debug("portion edited; delta=(grams - defaults.grams)g vs suggested (defaults.grams)g")
                    } else {
                        logger.debug("portion accepted as suggested")
                    }
                    onLog(grams, resolvedServingLabel, bucket)
                }
                .disabled(isSaving || !isValid)
                .overlay {
                    if isSaving {
                        ProgressView()
                    }
                }
            }
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
        MealBucketPicker(selection: $bucket)
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
            Text("\(FoodLogDisplayFormatter.formatNumber(value)) \(unit)")
                .helmType(.body, color: HelmColor.fgMuted)
        }
        .padding(HelmSpacing.sm)
        .background(HelmColor.gaugeTrack.opacity(0.2), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }

    private static func mapOrigin(_ origin: FoodProductRef.Origin) -> PortionOptionCatalog.FoodProductOrigin {
        switch origin {
        case .cofid: .cofid
        case .openFoodFacts: .openFoodFacts
        case .custom: .custom
        }
    }

    private static func countableMenuExtras(from mode: PortionInputMode) -> [ProducePortionOption] {
        guard case let .countable(config) = mode else { return [] }
        var extras = config.sizeOptions
        if let fixed = config.fixedUnitGrams {
            let label = config.unitNoun == "whole" ? "1 whole" : "1 \(config.unitNoun)"
            extras.insert(ProducePortionOption(label: label, grams: fixed), at: 0)
        }
        return extras
    }

    private static func initialServing(
        in options: [ProducePortionOption],
        servingLabel: String?,
        sizeLabel: String?
    ) -> ProducePortionOption? {
        if let servingLabel, let match = options.first(where: { $0.label == servingLabel }) {
            return match
        }
        if let sizeLabel, let match = options.first(where: { $0.label == sizeLabel }) {
            return match
        }
        return options.first
    }
}

/// MFP-style servings × serving-size controls.
struct ServingQuantityFields: View {
    let options: [ProducePortionOption]
    @Binding var servingsText: String
    @Binding var selectedLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("Servings")
                    .helmType(.label)
                TextField("1", text: $servingsText)
                    .keyboardType(.decimalPad)
                    .helmType(.number)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                    .accessibilityLabel("Number of servings")
            }

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("Serving size")
                    .helmType(.label)
                Menu {
                    ForEach(options, id: \.label) { option in
                        Button(option.label) {
                            HapticEngine.shared.play(.selection)
                            selectedLabel = option.label
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedOption?.label ?? "Serving")
                            .helmType(.body)
                        Spacer()
                        HelmIconView(.chevronDown, context: .inline)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                }
                .accessibilityLabel("Serving size")
            }
        }
    }

    private var selectedOption: ProducePortionOption? {
        options.first { $0.label == selectedLabel } ?? options.first
    }
}

#Preview("Portion packaged bar") {
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
            defaults: FoodPortionDefaults(
                grams: 60,
                servingLabel: "1 bar",
                prefersServingLabel: true,
                inputMode: .countable(CountablePortionConfig(
                    kind: .bar,
                    sizeOptions: [],
                    unitNoun: "bar",
                    pluralNoun: "bars",
                    fixedUnitGrams: 60
                ))
            ),
            isSaving: false,
            onLog: { _, _, _ in },
            onCancel: {}
        )
    }
    .helmTheme()
}

#Preview("Portion coop eggs") {
    NavigationStack {
        FoodPortionStepView(
            product: ResolvedFoodProduct(
                ref: FoodProductRef(
                    origin: .openFoodFacts,
                    externalID: "1234567890123",
                    displayName: "Coop 6 large free range eggs"
                ),
                per100gKcal: 154,
                per100gProteinG: 12.5,
                per100gCarbsG: 0.5,
                per100gFatG: 11,
                confidence: .branded,
                suggestedGrams: 300,
                servingLabel: nil,
                source: .openFoodFacts
            ),
            defaults: FoodPortionDefaults(
                grams: 50,
                servingLabel: "1 large eggs",
                prefersServingLabel: true,
                inputMode: .countable(CountablePortionConfig(
                    kind: .egg,
                    sizeOptions: PortionOptionCatalog.unitSizeOptions(forKeyword: "egg"),
                    unitNoun: "egg",
                    pluralNoun: "eggs"
                )),
                defaultQuantity: 1,
                defaultSizeLabel: "1 large"
            ),
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
