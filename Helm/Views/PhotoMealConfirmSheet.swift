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

    @Environment(\.helmReduceMotion) private var reduceMotion

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

                        if !currentEstimate.groundingWarnings.isEmpty {
                            groundingWarningsSection
                        }

                        if let direct = currentEstimate.visionDirectEstimate {
                            visionComparisonSection(direct)
                        }

                        MealBucketPicker(selection: $bucket)

                        MealLineItemEditor(
                            description: $description,
                            lineItems: $lineItems,
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

                        Button("Re-estimate with context") {
                            Task { await controller.reestimateFromConfirm() }
                        }
                        .buttonStyle(.helmSecondary)
                        .disabled(controller.isBusy)
                    }
                    .padding(HelmSpacing.md)
                }
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
                ToolbarItem(placement: .confirmationAction) {
                    if controller.isBusy {
                        ProgressView()
                    } else {
                        Button("Add") {
                            Task {
                                await controller.confirm(
                                    estimate: currentEstimate,
                                    name: description,
                                    bucket: bucket
                                )
                            }
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
    }

    private var confidenceLabel: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Estimate confidence: \(currentEstimate.confidence.rawValue.capitalized)")
                .helmType(.body, color: HelmColor.fgMuted)
            if currentEstimate.confidence == .low {
                Text("Signal decomposes the photo then matches ingredients to CoFID. Low usually means uncertain portions or a weak food match, not the same as Gemini’s percentage score.")
                    .helmType(.body, color: HelmColor.fgSecondary)
            }
        }
    }

    private var isValid: Bool {
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && currentEstimate.caloriesKcal > 0
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
                "Vision-only: \(Int(direct.caloriesKcal.rounded())) kcal · P \(Self.format(direct.proteinG)) · C \(Self.format(direct.carbsG)) · F \(Self.format(direct.fatG))"
            )
            .helmType(.body, color: HelmColor.fgSecondary)
            Text("CoFID grounded totals are shown below. Use ingredient rows to fix weak matches.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
        .padding(HelmSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.gaugeTrack.opacity(0.2), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}
