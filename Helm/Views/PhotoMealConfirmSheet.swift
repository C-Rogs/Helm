import Core
import DesignSystem
import SwiftUI

struct PhotoMealConfirmSheet: View {
    @Bindable var controller: PhotoMealController
    let initialEstimate: MealEstimate
    let previewImage: UIImage?

    @State private var description: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case description
        case calories
        case protein
        case carbs
        case fat
    }

    init(
        controller: PhotoMealController,
        initialEstimate: MealEstimate,
        previewImage: UIImage?
    ) {
        self.controller = controller
        self.initialEstimate = initialEstimate
        self.previewImage = previewImage
        _description = State(initialValue: initialEstimate.description)
        _calories = State(initialValue: Self.format(initialEstimate.caloriesKcal))
        _protein = State(initialValue: Self.format(initialEstimate.proteinG))
        _carbs = State(initialValue: Self.format(initialEstimate.carbsG))
        _fat = State(initialValue: Self.format(initialEstimate.fatG))
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

                    VStack(alignment: .leading, spacing: HelmSpacing.md) {
                        macroField("Description", text: $description, field: .description)
                            .textInputAutocapitalization(.sentences)
                        macroField("Calories", text: $calories, field: .calories, unit: "kcal")
                            .keyboardType(.numberPad)
                        macroField("Protein", text: $protein, field: .protein, unit: "g")
                            .keyboardType(.decimalPad)
                        macroField("Carbohydrates", text: $carbs, field: .carbs, unit: "g")
                            .keyboardType(.decimalPad)
                        macroField("Fat", text: $fat, field: .fat, unit: "g")
                            .keyboardType(.decimalPad)
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
                            await controller.confirm(estimate: builtEstimate(), name: description)
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
        Text("Estimate confidence: \(initialEstimate.confidence.rawValue.capitalized)")
            .helmType(.body, color: HelmColor.fgMuted)
    }

    private var isValid: Bool {
        parsed(calories) != nil
            && parsed(protein) != nil
            && parsed(carbs) != nil
            && parsed(fat) != nil
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func builtEstimate() -> MealEstimate {
        MealEstimate(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            caloriesKcal: parsed(calories) ?? initialEstimate.caloriesKcal,
            proteinG: parsed(protein) ?? initialEstimate.proteinG,
            carbsG: parsed(carbs) ?? initialEstimate.carbsG,
            fatG: parsed(fat) ?? initialEstimate.fatG,
            confidence: initialEstimate.confidence
        )
    }

    private func macroField(
        _ label: String,
        text: Binding<String>,
        field: Field,
        unit: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.label)
            HStack {
                TextField(label, text: text)
                    .focused($focusedField, equals: field)
                    .helmType(.body)
                if let unit {
                    Text(unit)
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
            .padding(HelmSpacing.sm)
            .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
    }

    private func parsed(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private static func format(_ value: Double) -> String {
        String(Int(value.rounded()))
    }
}
