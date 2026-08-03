import Core
import DesignSystem
import HealthKitIngest
import Persistence
import SwiftUI

struct MealEditSheet: View {
    let display: LoggedMealDisplay
    let isSaving: Bool
    let onSave: (String, [MealLineItemEditor.EditableLineItem], FoodPortionMacros?, MealBucket) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var lineItems: [MealLineItemEditor.EditableLineItem]
    @State private var quickAddKcalText: String
    @State private var quickAddProteinText: String
    @State private var quickAddCarbsText: String
    @State private var quickAddFatText: String
    @State private var bucket: MealBucket
    @State private var showsDeleteConfirm = false

    private let hasStoredLineItems: Bool
    private let isQuickAddStyle: Bool

    init(
        display: LoggedMealDisplay,
        isSaving: Bool,
        onSave: @escaping (String, [MealLineItemEditor.EditableLineItem], FoodPortionMacros?, MealBucket) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.display = display
        self.isSaving = isSaving
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel

        let store = PersistenceBootstrap.persistenceStore
        let storedItems = (try? store.foodLog.fetchLineItems(for: display.meal.id)) ?? []
        hasStoredLineItems = !storedItems.isEmpty
        isQuickAddStyle = storedItems.isEmpty
            && (display.meal.source == .quickAdd || display.meal.source == .alcohol)

        _name = State(initialValue: display.meal.name)
        _lineItems = State(initialValue: storedItems.enumerated().map { _, record in
            MealLineItemEditor.EditableLineItem(
                id: record.id.uuidString,
                item: MealLineItemTemplateMapping.lineItem(from: record),
                servingLabel: record.servingLabel
            )
        })
        let kcal = display.meal.energy?.kilocalories ?? 0
        _quickAddKcalText = State(initialValue: kcal > 0 ? String(Int(kcal.rounded())) : "")
        _quickAddProteinText = State(initialValue: Self.macroText(display.meal.proteinGrams))
        _quickAddCarbsText = State(initialValue: Self.macroText(display.meal.carbohydrateGrams))
        _quickAddFatText = State(initialValue: Self.macroText(display.meal.fatGrams))
        _bucket = State(initialValue: display.meal.bucket)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    Text(mealSourceLabel)
                        .helmType(.monoTag, color: HelmColor.fgMuted)

                    MealBucketPicker(selection: $bucket)

                    if hasStoredLineItems {
                        MealLineItemEditor(
                            description: $name,
                            lineItems: $lineItems
                        )
                    } else if isQuickAddStyle {
                        quickAddFields
                    } else {
                        simpleMealFields
                    }

                    Button(role: .destructive) {
                        showsDeleteConfirm = true
                    } label: {
                        Text("Delete entry")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.helmSecondary)
                    .disabled(isSaving)
                }
                .padding(HelmSpacing.md)
            }
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            saveTapped()
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showsDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the entry from Signal and Apple Health.")
            }
        }
    }

    private var mealSourceLabel: String {
        switch display.meal.source {
        case .healthKit: "Imported from Apple Health"
        case .manual: "Logged manually"
        case .photo: "Photo meal"
        case .barcode: "Barcode scan"
        case .quickAdd: "Quick add"
        case .alcohol: "Alcohol entry"
        case .template: "Meal template"
        }
    }

    private var quickAddFields: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("Name")
                    .helmType(.label)
                TextField("Meal name", text: $name)
                    .helmType(.body)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
            }

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("Calories")
                    .helmType(.label)
                TextField("kcal", text: $quickAddKcalText)
                    .keyboardType(.numberPad)
                    .helmType(.body)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
            }

            quickAddMacroField(title: "Protein", text: $quickAddProteinText, unit: "g")
            quickAddMacroField(title: "Carbohydrates", text: $quickAddCarbsText, unit: "g")
            quickAddMacroField(title: "Fat", text: $quickAddFatText, unit: "g")
        }
    }

    private func quickAddMacroField(title: String, text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(title)
                .helmType(.label)
            HStack(spacing: HelmSpacing.sm) {
                TextField(unit, text: text)
                    .keyboardType(.decimalPad)
                    .helmType(.body)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                Text(unit)
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
    }

    private static func macroText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        if value.rounded() == value {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private var quickAddMacros: FoodPortionMacros? {
        guard let kcal = Double(quickAddKcalText.trimmingCharacters(in: .whitespacesAndNewlines)), kcal > 0 else {
            return nil
        }
        return FoodPortionMacros(
            energyKcal: kcal,
            proteinG: Double(quickAddProteinText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            carbsG: Double(quickAddCarbsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            fatG: Double(quickAddFatText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        )
    }

    private var simpleMealFields: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("Name")
                    .helmType(.label)
                TextField("Meal name", text: $name)
                    .helmType(.body)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
            }

            if let kcal = display.meal.energy?.kilocalories, kcal > 0 {
                HStack {
                    Text("Calories")
                        .helmType(.body)
                    Spacer()
                    Text("\(Int(kcal.rounded())) kcal")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
                .padding(HelmSpacing.sm)
                .background(HelmColor.gaugeTrack.opacity(0.2), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
            }
        }
    }

    private func saveTapped() {
        onSave(name, lineItems, isQuickAddStyle ? quickAddMacros : nil, bucket)
    }
}

#if DEBUG
#Preview("Edit meal with line items") {
    let day = HelmDay(year: 2026, month: 7, day: 24)
    MealEditSheet(
        display: LoggedMealDisplay(
            meal: MealRecord(
                helmDay: day,
                name: "Oats and berries",
                loggedAt: Date(),
                bucket: .breakfast,
                energy: Energy(kilocalories: 420),
                proteinGrams: 18,
                carbohydrateGrams: 62,
                fatGrams: 9,
                source: .manual
            ),
            lineItems: [
                MealLineItemSummary(name: "Rolled oats", detail: "80 g", energyKcal: 300)
            ]
        ),
        isSaving: false,
        onSave: { _, _, _, _ in },
        onDelete: {},
        onCancel: {}
    )
    .helmTheme()
}
#endif
