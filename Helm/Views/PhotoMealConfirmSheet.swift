import CoachLLM
import Core
import DesignSystem
import NutritionKit
import SwiftUI

struct PhotoMealConfirmSheet: View {
    enum Mode {
        case draft
        case confirm
    }

    @Bindable var controller: PhotoMealController
    let initialEstimate: MealEstimate
    let previewImage: UIImage?
    let mode: Mode

    @State private var description: String
    @State private var lineItems: [MealLineItemEditor.EditableLineItem]
    @State private var bucket: MealBucket
    @State private var corrections = ""

    @Environment(\.helmReduceMotion) private var reduceMotion

    init(
        controller: PhotoMealController,
        initialEstimate: MealEstimate,
        previewImage: UIImage?,
        mode: Mode
    ) {
        self.controller = controller
        self.initialEstimate = initialEstimate
        self.previewImage = previewImage
        self.mode = mode
        let editableItems = initialEstimate.lineItems.map {
            MealLineItemEditor.EditableLineItem(id: UUID().uuidString, item: $0)
        }
        _description = State(initialValue: initialEstimate.description)
        _lineItems = State(initialValue: editableItems)
        _bucket = State(initialValue: controller.preferredBucket)
    }

    private var usesCofidGrounding: Bool {
        mode == .confirm && initialEstimate.scanMode == .cofidGrounded
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
            estimate.scanMode = initialEstimate.scanMode
            estimate.requiresRefinement = mode == .draft
            return estimate
        }
        var estimate = MacroAggregator.sum(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            lineItems: items
        )
        estimate.scanMode = initialEstimate.scanMode
        estimate.requiresRefinement = mode == .draft
        return estimate
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

                        confidenceLabel

                        if usesCofidGrounding, !currentEstimate.groundingWarnings.isEmpty {
                            groundingWarningsSection
                        }

                        if usesCofidGrounding, let direct = currentEstimate.visionDirectEstimate {
                            visionComparisonSection(direct)
                        }

                        if mode == .draft {
                            draftGuidance
                            correctionsField
                        }

                        MealBucketPicker(selection: $bucket)

                        MealLineItemEditor(
                            description: $description,
                            lineItems: $lineItems,
                            usesCofidGrounding: usesCofidGrounding,
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

                        if usesCofidGrounding {
                            Button("Re-estimate with context") {
                                Task { await controller.reestimateFromConfirm() }
                            }
                            .buttonStyle(.helmSecondary)
                            .disabled(controller.isBusy)
                        }

                        if mode == .draft {
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
                            .disabled(!canRefine || controller.isBusy)
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
            }
            .helmScreenBackground()
            .navigationTitle(mode == .draft ? "Review draft" : "Confirm meal")
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
    }

    private var draftGuidance: some View {
        Text("Review the draft below. Edit ingredients or add corrections, then update the estimate before logging.")
            .helmType(.body, color: HelmColor.fgMuted)
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

    private var confidenceLabel: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Estimate confidence: \(currentEstimate.confidence.rawValue.capitalized)")
                .helmType(.body, color: HelmColor.fgMuted)
            if usesCofidGrounding, currentEstimate.confidence == .low {
                Text("Signal decomposes the photo then matches ingredients to CoFID. Low usually means uncertain portions or a weak food match, not the same as Gemini’s percentage score.")
                    .helmType(.body, color: HelmColor.fgSecondary)
            }
        }
    }

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentEstimate.caloriesKcal > 0
    }

    private var canRefine: Bool {
        isValid
    }

    private var groundingWarningsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Grounding notes")
                .helmType(.label)
            ForEach(currentEstimate.groundingWarnings, id: \.self) { warning in
                Text(warning)
                    .helmType(.body, color: HelmColor.compromised)
            }
        }
        .padding(HelmSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.compromised.opacity(0.1), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }

    private func visionComparisonSection(_ direct: MealEstimate.VisionMacroComparison) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Direct vision comparison")
                .helmType(.label)
            Text(
                "Vision-only: \(FoodLogDisplayFormatter.formatNumber(direct.caloriesKcal)) kcal · P \(FoodLogDisplayFormatter.formatNumber(direct.proteinG)) · C \(FoodLogDisplayFormatter.formatNumber(direct.carbsG)) · F \(FoodLogDisplayFormatter.formatNumber(direct.fatG))"
            )
            .helmType(.body, color: HelmColor.fgSecondary)
            Text("CoFID grounded totals are shown below. Use ingredient rows to fix weak matches.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
        .padding(HelmSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.gaugeTrack.opacity(0.2), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }
}
