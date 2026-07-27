import Core
import DesignSystem
import HealthKitIngest
import NutritionKit
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
    @State private var selectedChipLabel: String?
    @State private var quantity: Int
    @State private var selectedSizeLabel: String?
    @State private var showsGramsOverride = false
    @FocusState private var gramsFocused: Bool

    private let produceOptions: [ProducePortionOption]
    private let inputMode: PortionInputMode
    private let countableConfig: CountablePortionConfig?

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
        inputMode = defaults.inputMode
        if case let .countable(config) = defaults.inputMode {
            countableConfig = config
        } else {
            countableConfig = nil
        }
        produceOptions = PortionOptionCatalog.options(
            for: product.ref.displayName,
            cofidID: product.ref.origin == .cofid ? product.ref.externalID : nil,
            origin: Self.mapOrigin(product.ref.origin),
            suggestedGrams: product.suggestedGrams ?? defaults.grams,
            servingLabel: product.servingLabel ?? defaults.servingLabel,
            defaultGrams: defaults.grams
        )
        _gramsText = State(initialValue: Self.format(defaults.grams))
        _servingLabel = State(initialValue: defaults.servingLabel ?? "")
        _bucket = State(initialValue: initialBucket)
        _selectedChipLabel = State(initialValue: defaults.servingLabel)
        _quantity = State(initialValue: defaults.defaultQuantity)
        _selectedSizeLabel = State(initialValue: defaults.defaultSizeLabel)
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

    private var resolvedServingLabel: String? {
        if let config = countableConfig {
            return CountablePortion.formatServingLabel(
                quantity: quantity,
                sizeLabel: selectedSizeLabel,
                config: config
            )
        }
        let trimmedServing = servingLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedServing.isEmpty {
            return trimmedServing
        }
        return selectedChipLabel
    }

    private var portionSummary: String? {
        guard let grams, let macros else { return nil }
        let gramsPart = "\(Self.format(grams)) g"
        let kcalPart = "\(Self.format(macros.energyKcal)) kcal"
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

                switch inputMode {
                case let .countable(config):
                    countablePortionSection(config: config)
                case .weight:
                    weightPortionSection
                }

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
                Button("Back", action: onCancel)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Log food") {
                guard let grams else { return }
                onLog(grams, resolvedServingLabel, bucket)
            }
            .buttonStyle(.helmPrimary)
            .disabled(!isValid || isSaving)
            .padding(HelmSpacing.md)
            .background(HelmColor.surface.opacity(0.96))
        }
        .onChange(of: quantity) { _, _ in
            syncCountableGramsFromSelection()
        }
        .onChange(of: selectedSizeLabel) { _, _ in
            syncCountableGramsFromSelection()
        }
    }

    // MARK: - Countable mode

    @ViewBuilder
    private func countablePortionSection(config: CountablePortionConfig) -> some View {
        if config.hasSizeVariants {
            sizeVariantSection(options: config.sizeOptions)
        }

        Stepper(value: $quantity, in: 1 ... 24) {
            HStack {
                Text("Quantity")
                    .helmType(.body)
                Spacer()
                Text("\(quantity)")
                    .helmType(.number)
            }
        }

        gramsOverrideSection
    }

    private func sizeVariantSection(options: [ProducePortionOption]) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Size")
                .helmType(.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HelmSpacing.xs) {
                    ForEach(sizeChips, id: \.label) { chip in
                        Button {
                            selectedSizeLabel = chip.label
                        } label: {
                            Text(chip.displayLabel)
                                .helmType(.monoTag)
                                .padding(.horizontal, HelmSpacing.sm)
                                .padding(.vertical, HelmSpacing.xs)
                                .background(
                                    selectedSizeLabel == chip.label
                                        ? HelmColor.buttonPrimaryBackground.opacity(0.25)
                                        : HelmColor.gaugeTrack.opacity(0.35),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.helmPressable)
                    }
                }
            }
        }
    }

    private var sizeChips: [SizeChip] {
        guard let config = countableConfig else { return [] }
        return config.sizeOptions.map { option in
            SizeChip(
                label: option.label,
                displayLabel: sizeDisplayLabel(from: option.label),
                grams: option.grams
            )
        }
    }

    private var gramsOverrideSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showsGramsOverride.toggle()
                }
            } label: {
                HStack {
                    Text(showsGramsOverride ? "Adjust weight" : "Adjust weight")
                        .helmType(.label)
                    Spacer()
                    HelmIconView(showsGramsOverride ? .chevronUp : .chevronDown, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                }
            }
            .buttonStyle(.helmPressable)

            if showsGramsOverride {
                gramsSection
            }
        }
    }

    // MARK: - Weight mode

    private var weightPortionSection: some View {
        Group {
            if !portionChips.isEmpty {
                portionChipSection
            }

            if defaults.prefersServingLabel {
                servingSection
            }

            gramsSection
        }
    }

    private var portionChips: [PortionChip] {
        produceOptions.map { PortionChip(label: $0.label, grams: $0.grams) }
    }

    private var portionChipSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Quick portions")
                .helmType(.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HelmSpacing.xs) {
                    ForEach(portionChips, id: \.label) { chip in
                        Button {
                            applyChip(chip)
                        } label: {
                            Text(chip.label)
                                .helmType(.monoTag)
                                .padding(.horizontal, HelmSpacing.sm)
                                .padding(.vertical, HelmSpacing.xs)
                                .background(
                                    selectedChipLabel == chip.label
                                        ? HelmColor.buttonPrimaryBackground.opacity(0.25)
                                        : HelmColor.gaugeTrack.opacity(0.35),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.helmPressable)
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

    private var servingSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text("Serving label")
                .helmType(.label)
            TextField("e.g. 1 medium apple", text: $servingLabel)
                .textInputAutocapitalization(.words)
                .helmType(.body)
                .padding(HelmSpacing.sm)
                .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                .onChange(of: servingLabel) { _, _ in
                    selectedChipLabel = nil
                }
        }
    }

    private var gramsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text("Grams")
                .helmType(.label)
            TextField("Grams", text: $gramsText)
                .focused($gramsFocused)
                .keyboardType(.decimalPad)
                .helmType(.body)
                .padding(HelmSpacing.sm)
                .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                .onChange(of: gramsText) { _, _ in
                    if countableConfig == nil {
                        selectedChipLabel = nil
                    }
                }
        }
    }

    private func applyChip(_ chip: PortionChip) {
        gramsText = Self.format(chip.grams)
        servingLabel = chip.label
        selectedChipLabel = chip.label
    }

    private func syncCountableGramsFromSelection() {
        guard let config = countableConfig else { return }
        let sizeOption = config.sizeOptions.first { $0.label == selectedSizeLabel }
            ?? CountablePortion.inferDefaultSize(from: product.ref.displayName, config: config)
        let unitGrams = CountablePortion.gramsPerUnit(
            sizeOption: sizeOption,
            config: config,
            fallbackGrams: defaults.grams
        )
        gramsText = Self.format(unitGrams * Double(quantity))
    }

    private func sizeDisplayLabel(from label: String) -> String {
        if let range = label.range(of: #"^\d+\s+"#, options: .regularExpression) {
            return String(label[range.upperBound...]).capitalized
        }
        return label.capitalized
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

    private static func mapOrigin(_ origin: FoodProductRef.Origin) -> PortionOptionCatalog.FoodProductOrigin {
        switch origin {
        case .cofid: .cofid
        case .openFoodFacts: .openFoodFacts
        case .custom: .custom
        }
    }
}

private struct PortionChip: Hashable {
    let label: String
    let grams: Double
}

private struct SizeChip: Hashable {
    let label: String
    let displayLabel: String
    let grams: Double
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
