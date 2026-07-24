import CoachLLM
import Core
import DesignSystem
import NutritionKit
import SwiftUI

struct PhotoMealConfirmSheet: View {
    @Bindable var controller: PhotoMealController
    let previewImage: UIImage?

    @State private var description: String
    @State private var lineItems: [MealLineItem]
    @State private var expandedItemIDs: Set<String>
    @FocusState private var focusedField: Field?

    private let lookup = NutritionLookup()

    private enum Field: Hashable {
        case description
        case grams(String)
    }

    init(
        controller: PhotoMealController,
        initialEstimate: MealEstimate,
        previewImage: UIImage?
    ) {
        self.controller = controller
        self.previewImage = previewImage
        _description = State(initialValue: initialEstimate.description)
        _lineItems = State(initialValue: initialEstimate.lineItems)
        _expandedItemIDs = State(initialValue: Set(initialEstimate.lineItems.map(\.id)))
    }

    private var currentEstimate: MealEstimate {
        if lineItems.isEmpty {
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
            lineItems: lineItems
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    if let previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
                    }

                    confidenceLabel

                    if lineItems.isEmpty {
                        legacyTotalsFallback
                    } else {
                        ingredientsSection
                        totalsSection
                    }
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Confirm meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.cancel()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: HelmSpacing.sm) {
                    Button("Log to Health") {
                        Task {
                            await controller.confirm(estimate: currentEstimate, name: description)
                        }
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(!isValid)
                }
                .padding(HelmSpacing.md)
                .background(HelmColor.surface.opacity(0.96))
            }
        }
    }

    private var confidenceLabel: some View {
        Text("Estimate confidence: \(currentEstimate.confidence.rawValue.capitalized)")
            .helmType(.body, color: HelmColor.fgMuted)
    }

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentEstimate.caloriesKcal > 0
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Ingredients")
                .helmType(.label)

            ForEach(lineItems) { item in
                ingredientRow(item)
            }
        }
    }

    private func ingredientRow(_ item: MealLineItem) -> some View {
        let isExpanded = expandedItemIDs.contains(item.id)

        return VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Button {
                if isExpanded {
                    expandedItemIDs.remove(item.id)
                } else {
                    expandedItemIDs.insert(item.id)
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
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(HelmColor.fgMuted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack {
                    Text("Grams")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                    TextField("Grams", text: gramsBinding(for: item))
                        .focused($focusedField, equals: .grams(item.id))
                        .keyboardType(.decimalPad)
                        .helmType(.body)
                        .padding(HelmSpacing.sm)
                        .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                }
            }
        }
        .padding(HelmSpacing.sm)
        .background(HelmColor.gaugeTrack.opacity(0.2), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
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

    private var legacyTotalsFallback: some View {
        Text("No ingredient breakdown available for this estimate.")
            .helmType(.body, color: HelmColor.fgMuted)
    }

    private func gramsBinding(for item: MealLineItem) -> Binding<String> {
        Binding(
            get: {
                Self.format(item.grams)
            },
            set: { newValue in
                guard let grams = Double(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                guard let index = lineItems.firstIndex(where: { $0.id == item.id }) else { return }
                lineItems[index] = MacroAggregator.recomputeLineItem(item, grams: grams, lookup: lookup)
            }
        )
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
