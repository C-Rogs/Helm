import CoachLLM
import Core
import DesignSystem
import NutritionKit
import SwiftUI

struct PhotoMealConfirmSheet: View {
    @Bindable var controller: PhotoMealController
    let initialEstimate: MealEstimate
    let previewImage: UIImage?

    @State private var description: String
    @State private var lineItems: [MealLineItemEditor.EditableLineItem]
    @State private var bucket: MealBucket
    @State private var corrections = ""

    @Environment(\.helmReduceMotion) private var reduceMotion

    init(
        controller: PhotoMealController,
        initialEstimate: MealEstimate,
        previewImage: UIImage?
    ) {
        self.controller = controller
        self.initialEstimate = initialEstimate
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
            var estimate = MealEstimate(
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                caloriesKcal: 0,
                proteinG: 0,
                carbsG: 0,
                fatG: 0,
                confidence: .medium
            )
            estimate.scanMode = .visionDirect
            estimate.requiresRefinement = false
            return estimate
        }
        var estimate = MacroAggregator.sum(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            lineItems: items
        )
        estimate.scanMode = .visionDirect
        estimate.requiresRefinement = false
        return estimate
    }

    private var hasCorrections: Bool {
        !corrections.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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

                        Text("Estimate confidence: \(currentEstimate.confidence.rawValue.capitalized)")
                            .helmType(.body, color: HelmColor.fgMuted)

                        Text("Review the draft. Edit ingredients and add the meal, or type corrections and update the estimate first.")
                            .helmType(.body, color: HelmColor.fgMuted)

                        correctionsField

                        MealBucketPicker(selection: $bucket)

                        MealLineItemEditor(
                            description: $description,
                            lineItems: $lineItems,
                            usesCofidGrounding: false,
                            onFocusedScrollIDChange: { scrollID in
                                guard let scrollID else { return }
                                withAnimation(
                                    HelmMotion.animation(
                                        HelmMotion.settleAnimation,
                                        reduceMotion: reduceMotion
                                    )
                                ) {
                                    proxy.scrollTo(scrollID, anchor: .center)
                                }
                            }
                        )

                        if !controller.userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Context: \(controller.userNotes)")
                                .helmType(.body, color: HelmColor.fgSecondary)
                        }

                        if hasCorrections {
                            HelmActionButton(
                                "Update estimate",
                                phase: controller.isBusy ? .loading : .idle,
                                successTitle: "Updated"
                            ) {
                                Task {
                                    await controller.refineDraft(
                                        corrections: corrections,
                                        editedEstimate: currentEstimate
                                    )
                                }
                            }
                            .disabled(!isValid || controller.isBusy)
                        } else {
                            HelmActionButton(
                                "Add meal",
                                phase: controller.isBusy ? .loading : .idle,
                                successTitle: "Added"
                            ) {
                                Task {
                                    await controller.confirm(
                                        estimate: currentEstimate,
                                        name: description,
                                        bucket: bucket
                                    )
                                }
                            }
                            .disabled(!isValid || controller.isBusy)
                        }
                    }
                    .padding(HelmSpacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .helmScreenBackground()
            .navigationTitle("Confirm meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.cancel()
                    }
                    .disabled(controller.isBusy)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var correctionsField: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Corrections")
                .helmType(.label)
            TextField(
                "e.g. salmon is thick-cut, not sashimi; rice is about 1 cup",
                text: $corrections,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2 ... 5)
        }
    }

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentEstimate.caloriesKcal > 0
    }
}
