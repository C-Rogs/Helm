import CoachLLM
import Core
import DesignSystem
import NutritionKit
import SwiftUI

struct PhotoMealConfirmSheet: View {
    @Bindable var controller: PhotoMealController
    let previewImage: UIImage?

    @State private var description: String
    @State private var lineItems: [MealLineItemEditor.EditableLineItem]
    @State private var bucket: MealBucket

    private let lookup = NutritionLookup()

    init(
        controller: PhotoMealController,
        initialEstimate: MealEstimate,
        previewImage: UIImage?
    ) {
        self.controller = controller
        self.previewImage = previewImage
        let editableItems = initialEstimate.lineItems.map {
            MealLineItemEditor.EditableLineItem(id: UUID().uuidString, item: $0)
        }
        _description = State(initialValue: initialEstimate.description)
        _lineItems = State(initialValue: editableItems)
        _bucket = State(initialValue: controller.preferredBucket)
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

                    MealBucketPicker(selection: $bucket)

                    MealLineItemEditor(description: $description, lineItems: $lineItems)

                    if !controller.userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Context: \(controller.userNotes)")
                            .helmType(.body, color: HelmColor.fgSecondary)
                    }

                    Button("Re-estimate with context") {
                        Task { await controller.reestimateFromConfirm() }
                    }
                    .buttonStyle(.helmSecondary)
                    .disabled(controller.isBusy)
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
                            await controller.confirm(
                                estimate: currentEstimate,
                                name: description,
                                bucket: bucket
                            )
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
}
