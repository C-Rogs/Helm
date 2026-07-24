import Core
import DesignSystem
import NutritionKit
import SwiftUI

/// Shared ingredient editor for photo confirm and manual meal correction.
struct MealLineItemEditor: View {
    struct EditableLineItem: Identifiable {
        let id: String
        var item: MealLineItem
    }

    private enum Field: Hashable {
        case description
        case name(String)
        case grams(String)
    }

    @Binding var description: String
    @Binding var lineItems: [EditableLineItem]
    var showsTotals: Bool = true

    @State private var expandedItemIDs: Set<String> = []
    @State private var nameQueryItemID: String?
    @FocusState private var focusedField: Field?

    private let lookup = NutritionLookup()

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
        .onAppear {
            if expandedItemIDs.isEmpty {
                expandedItemIDs = Set(lineItems.map(\.id))
            }
        }
        .onChange(of: lineItems.count) { _, _ in
            for entry in lineItems where !expandedItemIDs.contains(entry.id) {
                expandedItemIDs.insert(entry.id)
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

        return VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Button {
                if isExpanded {
                    expandedItemIDs.remove(entry.id)
                } else {
                    expandedItemIDs.insert(entry.id)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text(item.name)
                            .helmType(.body)
                        Text("\(Self.format(item.grams)) g · \(Self.format(item.caloriesKcal)) kcal")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
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
            }
        }
        .padding(HelmSpacing.sm)
        .background(HelmColor.gaugeTrack.opacity(0.2), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
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

            readOnlyRow("Calories", value: currentEstimate.caloriesKcal, unit: "kcal")
            readOnlyRow("Protein", value: currentEstimate.proteinG, unit: "g")
            readOnlyRow("Carbohydrates", value: currentEstimate.carbsG, unit: "g")
            readOnlyRow("Fat", value: currentEstimate.fatG, unit: "g")
        }
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
