import Core
import DesignSystem
import NutritionKit
import SwiftUI

/// Shared ingredient editor for photo confirm and manual meal correction.
struct MealLineItemEditor: View {
    struct EditableLineItem: Identifiable {
        let id: String
        var item: MealLineItem
        var servingLabel: String?

        init(id: String, item: MealLineItem, servingLabel: String? = nil) {
            self.id = id
            self.item = item
            self.servingLabel = servingLabel
        }
    }

    private struct CountableEditorState {
        var quantity: Int
        var selectedSizeLabel: String?
        var showsGramsOverride = false
    }

    private enum Field: Hashable {
        case description
        case name(String)
        case grams(String)
    }

    @Binding var description: String
    @Binding var lineItems: [EditableLineItem]
    var showsTotals: Bool = true
    var onFocusedScrollIDChange: ((String?) -> Void)? = nil

    @Bindable private var focusModePreferences = FocusModePreferences.shared
    @State private var expandedItemIDs: Set<String> = []
    @State private var nameQueryItemID: String?
    @State private var countableStates: [String: CountableEditorState] = [:]
    @FocusState private var focusedField: Field?
    @Environment(\.helmReduceMotion) private var reduceMotion

    private let lookup = NutritionLookup()

    private var isSpotlightActive: Bool {
        focusModePreferences.isFocusModeEnabled && focusedField != nil
    }

    private var currentEstimate: MealEstimate {
        let items = lineItems.map(\.item)
        if items.isEmpty {
            return MealEstimate(
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                caloriesKcal: 0,
                proteinG: 0,
                carbsG: 0,
                fatG: 0,
                confidence: .medium
            )
        }
        return MacroAggregator.sum(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            lineItems: items
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            if lineItems.isEmpty {
                Text("No ingredient breakdown available for this estimate.")
                    .helmType(.body, color: HelmColor.fgMuted)
            } else {
                ingredientsSection
                if showsTotals {
                    totalsSection
                }
            }
        }
        .animation(
            HelmMotion.animation(
                HelmMotion.settleAnimation,
                reduceMotion: reduceMotion
            ),
            value: focusedField
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                    HapticEngine.shared.play(.selection)
                }
            }
        }
        .onAppear {
            if expandedItemIDs.isEmpty {
                expandedItemIDs = Set(lineItems.map(\.id))
            }
            seedCountableStatesIfNeeded()
        }
        .onChange(of: lineItems.count) { _, _ in
            for entry in lineItems where !expandedItemIDs.contains(entry.id) {
                expandedItemIDs.insert(entry.id)
            }
            seedCountableStatesIfNeeded()
        }
        .onChange(of: focusedField) { _, newValue in
            let scrollID = scrollID(for: newValue)
            onFocusedScrollIDChange?(scrollID)
            if newValue != nil {
                HapticEngine.shared.play(.selection)
            }
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Ingredients")
                .helmType(.label)

            ForEach(lineItems) { entry in
                ingredientRow(entry)
            }
        }
    }

    private func ingredientRow(_ entry: EditableLineItem) -> some View {
        let item = entry.item
        let isExpanded = expandedItemIDs.contains(entry.id)
        let title = FoodLogDisplayFormatter.primaryTitle(
            displayName: item.name,
            servingLabel: entry.servingLabel
        )
        let detail = FoodLogDisplayFormatter.secondaryDetail(
            displayName: item.name,
            servingLabel: entry.servingLabel,
            grams: item.grams
        )

        return VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Button {
                if isExpanded {
                    expandedItemIDs.remove(entry.id)
                } else {
                    expandedItemIDs.insert(entry.id)
                    seedCountableStateIfNeeded(for: entry)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text(title)
                            .helmType(.body)
                        Text("\(detail) · \(Self.format(item.caloriesKcal)) kcal")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                        Text(cofidMatchLabel(for: item))
                            .helmType(.monoTag, color: cofidMatchColor(for: item))
                    }
                    Spacer()
                    HelmIconView(isExpanded ? .chevronUp : .chevronDown, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                }
            }
            .buttonStyle(.helmPressable)

            if isExpanded {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text("Food")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                        TextField("Food name", text: nameBinding(for: entry))
                            .focused($focusedField, equals: .name(entry.id))
                            .textInputAutocapitalization(.words)
                            .helmType(.body)
                            .padding(HelmSpacing.sm)
                            .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                            .onChange(of: focusedField) { _, newValue in
                                if newValue != .name(entry.id) {
                                    nameQueryItemID = nil
                                }
                            }
                    }

                    if nameQueryItemID == entry.id {
                        suggestionList(for: entry)
                    }

                    if let config = countableConfig(for: entry) {
                        countableEditor(for: entry, config: config)
                    } else {
                        gramsEditor(for: entry)
                    }
                }
            }
        }
        .padding(HelmSpacing.sm)
        .background(HelmColor.gaugeTrack.opacity(0.2), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        .spotlightEffect(
            isFocused: isIngredientFocused(entry.id),
            isFocusModeEnabled: isSpotlightActive
        )
        .id(Self.ingredientScrollID(entry.id))
    }

    private func isIngredientFocused(_ entryID: String) -> Bool {
        switch focusedField {
        case .name(let id), .grams(let id):
            return id == entryID
        default:
            return false
        }
    }

    private func scrollID(for field: Field?) -> String? {
        switch field {
        case .description:
            return Self.descriptionScrollID
        case .name(let id), .grams(let id):
            return Self.ingredientScrollID(id)
        case nil:
            return nil
        }
    }

    private static func ingredientScrollID(_ entryID: String) -> String {
        "meal-ingredient-\(entryID)"
    }

    private static let descriptionScrollID = "meal-description"

    @ViewBuilder
    private func countableEditor(for entry: EditableLineItem, config: CountablePortionConfig) -> some View {
        let state = countableStates[entry.id] ?? defaultCountableState(for: entry, config: config)

        if config.hasSizeVariants {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("Size")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: HelmSpacing.xs) {
                        ForEach(config.sizeOptions, id: \.label) { option in
                            Button {
                                updateCountableState(for: entry.id) { $0.selectedSizeLabel = option.label }
                                applyCountableUpdate(for: entry.id, config: config)
                            } label: {
                                Text(sizeDisplayLabel(from: option.label))
                                    .helmType(.monoTag)
                                    .padding(.horizontal, HelmSpacing.sm)
                                    .padding(.vertical, HelmSpacing.xxs)
                                    .background(
                                        state.selectedSizeLabel == option.label
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

        Stepper(value: quantityBinding(for: entry.id, config: config), in: 1 ... 24) {
            HStack {
                Text("Quantity")
                    .helmType(.body)
                Spacer()
                Text("\(state.quantity)")
                    .helmType(.number)
            }
        }

        Button {
            updateCountableState(for: entry.id) { $0.showsGramsOverride.toggle() }
        } label: {
            HStack {
                Text("Adjust weight")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Spacer()
                HelmIconView(state.showsGramsOverride ? .chevronUp : .chevronDown, context: .inline)
                    .foregroundStyle(HelmColor.fgMuted)
            }
        }
        .buttonStyle(.helmPressable)

        if state.showsGramsOverride {
            gramsEditor(for: entry)
        }
    }

    private func gramsEditor(for entry: EditableLineItem) -> some View {
        HStack {
            Text("Grams")
                .helmType(.monoTag, color: HelmColor.fgMuted)
            TextField("Grams", text: gramsBinding(for: entry))
                .focused($focusedField, equals: .grams(entry.id))
                .keyboardType(.decimalPad)
                .helmType(.body)
                .padding(HelmSpacing.sm)
                .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
    }

    @ViewBuilder
    private func suggestionList(for entry: EditableLineItem) -> some View {
        let suggestions = lookup.suggestionNames(matching: entry.item.name)
        if suggestions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text("Matches")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        applyFoodName(suggestion, to: entry.id)
                    } label: {
                        Text(suggestion)
                            .helmType(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.helmPressable)
                }
            }
        }
    }

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Totals")
                .helmType(.label)

            macroField("Description", text: $description, field: .description)
                .textInputAutocapitalization(.sentences)
                .spotlightEffect(
                    isFocused: focusedField == .description,
                    isFocusModeEnabled: isSpotlightActive
                )
                .id(Self.descriptionScrollID)

            readOnlyRow("Calories", value: currentEstimate.caloriesKcal, unit: "kcal")
            readOnlyRow("Protein", value: currentEstimate.proteinG, unit: "g")
            readOnlyRow("Carbohydrates", value: currentEstimate.carbsG, unit: "g")
            readOnlyRow("Fat", value: currentEstimate.fatG, unit: "g")
        }
    }

    private func countableConfig(for entry: EditableLineItem) -> CountablePortionConfig? {
        CountablePortion.detect(for: entry.item.name, servingLabel: entry.servingLabel)
    }

    private func seedCountableStatesIfNeeded() {
        for entry in lineItems {
            seedCountableStateIfNeeded(for: entry)
        }
    }

    private func seedCountableStateIfNeeded(for entry: EditableLineItem) {
        guard countableStates[entry.id] == nil else { return }
        guard let config = countableConfig(for: entry) else { return }
        countableStates[entry.id] = defaultCountableState(for: entry, config: config)
    }

    private func defaultCountableState(
        for entry: EditableLineItem,
        config: CountablePortionConfig
    ) -> CountableEditorState {
        let parsed = entry.servingLabel.flatMap { CountablePortion.parseServingLabel($0, config: config) }
        let unitGrams = bootstrapUnitGrams(for: entry, config: config, parsed: parsed)
        return CountableEditorState(
            quantity: parsed?.quantity ?? max(Int((entry.item.grams / max(unitGrams, 1)).rounded()), 1),
            selectedSizeLabel: parsed?.sizeOption?.label
                ?? CountablePortion.inferDefaultSize(from: entry.item.name, config: config)?.label
        )
    }

    private func quantityBinding(for entryID: String, config: CountablePortionConfig) -> Binding<Int> {
        Binding(
            get: { countableStates[entryID]?.quantity ?? 1 },
            set: { newValue in
                updateCountableState(for: entryID) { $0.quantity = newValue }
                applyCountableUpdate(for: entryID, config: config)
            }
        )
    }

    private func applyCountableUpdate(for entryID: String, config: CountablePortionConfig) {
        guard let index = lineItems.firstIndex(where: { $0.id == entryID }) else { return }
        guard let state = countableStates[entryID] else { return }

        let entry = lineItems[index]
        let sizeOption = config.sizeOptions.first { $0.label == state.selectedSizeLabel }
        let unitGrams = CountablePortion.gramsPerUnit(
            sizeOption: sizeOption,
            config: config,
            fallbackGrams: entry.item.grams
        )
        let totalGrams = unitGrams * Double(state.quantity)
        let label = CountablePortion.formatServingLabel(
            quantity: state.quantity,
            sizeLabel: state.selectedSizeLabel,
            config: config
        )

        lineItems[index].item = recomputeLineItem(
            name: entry.item.name,
            grams: totalGrams,
            from: entry.item
        )
        lineItems[index].servingLabel = label
    }

    private func unitGrams(for entry: EditableLineItem, config: CountablePortionConfig) -> Double {
        if let state = countableStates[entry.id] {
            let sizeOption = config.sizeOptions.first { $0.label == state.selectedSizeLabel }
            return CountablePortion.gramsPerUnit(
                sizeOption: sizeOption,
                config: config,
                fallbackGrams: entry.item.grams
            )
        }

        let parsed = entry.servingLabel.flatMap { CountablePortion.parseServingLabel($0, config: config) }
        return bootstrapUnitGrams(for: entry, config: config, parsed: parsed)
    }

    private func bootstrapUnitGrams(
        for entry: EditableLineItem,
        config: CountablePortionConfig,
        parsed: (quantity: Int, sizeOption: ProducePortionOption?)?
    ) -> Double {
        let sizeOption = parsed?.sizeOption
            ?? CountablePortion.inferDefaultSize(from: entry.item.name, config: config)
        return CountablePortion.gramsPerUnit(
            sizeOption: sizeOption,
            config: config,
            fallbackGrams: entry.item.grams
        )
    }

    private func updateCountableState(for entryID: String, update: (inout CountableEditorState) -> Void) {
        var state = countableStates[entryID] ?? CountableEditorState(quantity: 1, selectedSizeLabel: nil)
        update(&state)
        countableStates[entryID] = state
    }

    private func recomputeLineItem(name: String, grams: Double, from item: MealLineItem) -> MealLineItem {
        if let resolved = lookup.resolve(item: name) {
            return MacroAggregator.lineItem(
                name: name,
                grams: grams,
                resolved: resolved,
                itemConfidence: item.matchConfidence
            )
        }

        let renamed = MealLineItem(
            name: name,
            grams: item.grams,
            caloriesKcal: item.caloriesKcal,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            usdaMatchID: item.usdaMatchID,
            matchConfidence: item.matchConfidence
        )
        return MacroAggregator.recomputeLineItem(renamed, grams: grams, lookup: lookup)
    }

    private func nameBinding(for entry: EditableLineItem) -> Binding<String> {
        Binding(
            get: { entry.item.name },
            set: { newValue in
                guard let index = lineItems.firstIndex(where: { $0.id == entry.id }) else { return }
                let current = lineItems[index].item
                lineItems[index].item = recomputeLineItem(
                    name: newValue,
                    grams: current.grams,
                    from: current
                )
                nameQueryItemID = entry.id
            }
        )
    }

    private func gramsBinding(for entry: EditableLineItem) -> Binding<String> {
        Binding(
            get: {
                Self.format(entry.item.grams)
            },
            set: { newValue in
                guard let grams = Double(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                guard let index = lineItems.firstIndex(where: { $0.id == entry.id }) else { return }
                let current = lineItems[index].item
                lineItems[index].item = MacroAggregator.recomputeLineItem(
                    current,
                    grams: grams,
                    lookup: lookup
                )
            }
        )
    }

    private func applyFoodName(_ name: String, to entryID: String) {
        guard let index = lineItems.firstIndex(where: { $0.id == entryID }) else { return }
        let current = lineItems[index].item
        lineItems[index].item = recomputeLineItem(
            name: name,
            grams: current.grams,
            from: current
        )
        nameQueryItemID = nil
        focusedField = .grams(entryID)
    }

    private func sizeDisplayLabel(from label: String) -> String {
        if let range = label.range(of: #"^\d+\s+"#, options: .regularExpression) {
            return String(label[range.upperBound...]).capitalized
        }
        return label.capitalized
    }

    private func macroField(
        _ label: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.label)
            TextField(label, text: text)
                .focused($focusedField, equals: field)
                .helmType(.body)
                .padding(HelmSpacing.sm)
                .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
    }

    private func readOnlyRow(_ label: String, value: Double, unit: String) -> some View {
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

    private func cofidMatchLabel(for item: MealLineItem) -> String {
        if item.usesGenericCofidFallback {
            return "CoFID: generic dish (no match)"
        }
        if let cofid = item.cofidDescription {
            let quality = switch item.matchConfidence {
            case .high: "strong match"
            case .medium: "partial match"
            case .low: "weak match"
            }
            return "CoFID: \(cofid) · \(quality)"
        }
        return "CoFID match unknown"
    }

    private func cofidMatchColor(for item: MealLineItem) -> Color {
        if item.usesGenericCofidFallback || item.matchConfidence == .low {
            return HelmColor.compromised
        }
        if item.matchConfidence == .medium {
            return HelmColor.fgSecondary
        }
        return HelmColor.fgMuted
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}

#Preview("Meal line item editor") {
    ScrollView {
        MealLineItemEditor(
            description: .constant("Chicken rice bowl"),
            lineItems: .constant([
                MealLineItemEditor.EditableLineItem(
                    id: "1",
                    item: MealLineItem(
                        name: "Chicken breast",
                        grams: 140,
                        caloriesKcal: 165,
                        proteinG: 31,
                        carbsG: 0,
                        fatG: 3.6,
                        matchConfidence: .high
                    )
                ),
                MealLineItemEditor.EditableLineItem(
                    id: "2",
                    item: MealLineItem(
                        name: "White rice cooked",
                        grams: 180,
                        caloriesKcal: 234,
                        proteinG: 4.8,
                        carbsG: 51,
                        fatG: 0.4,
                        matchConfidence: .medium
                    )
                )
            ])
        )
        .padding(HelmSpacing.md)
    }
    .helmTheme()
}

#Preview("Meal line item editor eggs") {
    ScrollView {
        MealLineItemEditor(
            description: .constant("Coop 6 large free range eggs"),
            lineItems: .constant([
                MealLineItemEditor.EditableLineItem(
                    id: "1",
                    item: MealLineItem(
                        name: "Coop 6 large free range eggs",
                        grams: 150,
                        caloriesKcal: 231,
                        proteinG: 19,
                        carbsG: 1,
                        fatG: 17,
                        matchConfidence: .high
                    ),
                    servingLabel: "3 large eggs"
                )
            ])
        )
        .padding(HelmSpacing.md)
    }
    .helmTheme()
}
