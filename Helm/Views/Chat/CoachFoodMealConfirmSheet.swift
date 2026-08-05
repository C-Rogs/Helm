import CoachLLM
import Core
import DesignSystem
import NutritionKit
import SwiftUI

struct CoachFoodMealConfirmSheet: View {
    let coachReply: String
    let initialEstimate: MealEstimate
    let initialBucket: MealBucket
    let isSaving: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onConfirm: (MealEstimate, String, MealBucket) -> Void

    @State private var description: String
    @State private var lineItems: [MealLineItemEditor.EditableLineItem]
    @State private var bucket: MealBucket

    @Environment(\.helmReduceMotion) private var reduceMotion

    init(
        state: CoachFoodMealConfirmState,
        isSaving: Bool,
        errorMessage: String? = nil,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (MealEstimate, String, MealBucket) -> Void
    ) {
        coachReply = state.coachReply
        initialEstimate = state.estimate
        initialBucket = state.bucket
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onConfirm = onConfirm

        let editableItems = state.estimate.lineItems.map {
            MealLineItemEditor.EditableLineItem(id: UUID().uuidString, item: $0)
        }
        _description = State(initialValue: state.estimate.description)
        _lineItems = State(initialValue: editableItems)
        _bucket = State(initialValue: state.bucket)
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
                confidence: initialEstimate.confidence
            )
        }
        return MacroAggregator.sum(
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            lineItems: items,
            groundingWarnings: initialEstimate.groundingWarnings,
            decompositionAuditJSON: initialEstimate.decompositionAuditJSON
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                            if !coachReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(coachReply)
                                    .helmType(.body, color: HelmColor.fgSecondary)
                            }

                            confidenceLabel

                            if !currentEstimate.groundingWarnings.isEmpty {
                                groundingWarningsSection
                            }

                            if let errorMessage, !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .helmType(.body, color: HelmColor.depleted)
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
                        }
                        .padding(HelmSpacing.md)
                        .allowsHitTesting(!isSaving)
                    }
                }

                if isSaving {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    CoachAIProgressCard(
                        eyebrow: "COACH",
                        title: "Logging meal",
                        completedSteps: ["Confirmed"],
                        currentStep: "Writing to diary…",
                        isImpactful: true
                    )
                    .helmScreenPadding()
                }
            }
            .helmScreenBackground()
            .navigationTitle("Confirm meal")
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
                        Button("Log meal") {
                            onConfirm(currentEstimate, description, bucket)
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
                Text("Review each ingredient row. Tap weak matches to pick a better CoFID food.")
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
}
