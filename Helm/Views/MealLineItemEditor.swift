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

    private struct PortionEditorState {
        var servingsText: String
        var selectedLabel: String
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
    @State private var portionStates: [String: PortionEditorState] = [:]
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
            seedPortionStatesIfNeeded()
        }
        .onChange(of: lineItems.count) { _, _ in
            for entry in lineItems where !expandedItemIDs.contains(entry.id) {
                expandedItemIDs.insert(entry.id)
            }
            seedPortionStatesIfNeeded()
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
                    seedPortionStateIfNeeded(for: entry)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text(title)
                            .helmType(.body)
                        Text("\(detail) · \(FoodLogDisplayFormatter.formatNumber(item.caloriesKcal)) kcal")
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

                    ServingQuantityFields(
                        options: servingOptions(for: entry),
                        servingsText: portionServingsBinding(for: entry.id),
                        selectedLabel: portionSizeBinding(for: entry.id)
                    )
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

    private func servingOptions(for entry: EditableLineItem) -> [ProducePortionOption] {
        let state = portionStates[entry.id]
        let unitGramsHint: Double = {
            if let state, let servings = PortionServings.parse(state.servingsText), servings > 0 {
                return entry.item.grams / servings
            }
            return entry.item.grams
        }()
        let labelHint = state?.selectedLabel ?? entry.servingLabel
        var extras: [ProducePortionOption] = []
        if let config = CountablePortion.detect(
            for: entry.item.name,
            suggestedGrams: unitGramsHint,
            servingLabel: labelHint
        ) {
            extras.append(contentsOf: config.sizeOptions)
            if let fixed = config.fixedUnitGrams {
                let label = config.unitNoun == "whole" ? "1 whole" : "1 \(config.unitNoun)"
                extras.insert(ProducePortionOption(label: label, grams: fixed), at: 0)
            }
        }
        return PortionOptionCatalog.servingMenu(
            for: entry.item.name,
            suggestedGrams: unitGramsHint,
            servingLabel: labelHint,
            extra: extras
        )
    }

    private func seedPortionStatesIfNeeded() {
        for entry in lineItems {
            seedPortionStateIfNeeded(for: entry)
        }
    }

    private func seedPortionStateIfNeeded(for entry: EditableLineItem) {
        guard portionStates[entry.id] == nil else { return }
        let options = servingOptions(for: entry)
        let selected = options.first { $0.label == entry.servingLabel }
            ?? options.first
        let unitGrams = selected?.grams ?? max(entry.item.grams, 1)
        portionStates[entry.id] = PortionEditorState(
            servingsText: PortionServings.format(
                PortionServings.servings(grams: entry.item.grams, unitGrams: unitGrams)
            ),
            selectedLabel: selected?.label ?? "1 g"
        )
    }

    private func portionServingsBinding(for entryID: String) -> Binding<String> {
        Binding(
            get: { portionStates[entryID]?.servingsText ?? "1" },
            set: { newValue in
                if portionStates[entryID] == nil, let entry = lineItems.first(where: { $0.id == entryID }) {
                    seedPortionStateIfNeeded(for: entry)
                }
                portionStates[entryID]?.servingsText = newValue
                applyPortionUpdate(for: entryID)
            }
        )
    }

    private func portionSizeBinding(for entryID: String) -> Binding<String> {
        Binding(
            get: { portionStates[entryID]?.selectedLabel ?? "1 g" },
            set: { newValue in
                if portionStates[entryID] == nil, let entry = lineItems.first(where: { $0.id == entryID }) {
                    seedPortionStateIfNeeded(for: entry)
                }
                portionStates[entryID]?.selectedLabel = newValue
                applyPortionUpdate(for: entryID)
            }
        )
    }

    private func applyPortionUpdate(for entryID: String) {
        guard let index = lineItems.firstIndex(where: { $0.id == entryID }) else { return }
        guard let state = portionStates[entryID] else { return }
        let entry = lineItems[index]
        let options = servingOptions(for: entry)
        let option = options.first { $0.label == state.selectedLabel } ?? options.first
        guard let option, let servings = PortionServings.parse(state.servingsText) else { return }
        let totalGrams = PortionServings.totalGrams(servings: servings, unitGrams: option.grams)
        lineItems[index].item = recomputeLineItem(
            name: entry.item.name,
            grams: totalGrams,
            from: entry.item
        )
        lineItems[index].servingLabel = PortionServings.displayLabel(
            servings: servings,
            servingSize: option.label
        )
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

    private func applyFoodName(_ name: String, to entryID: String) {
        guard let index = lineItems.firstIndex(where: { $0.id == entryID }) else { return }
        let current = lineItems[index].item
        lineItems[index].item = recomputeLineItem(
            name: name,
            grams: current.grams,
            from: current
        )
        nameQueryItemID = nil
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
            Text("\(FoodLogDisplayFormatter.formatNumber(value)) \(unit)")
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
