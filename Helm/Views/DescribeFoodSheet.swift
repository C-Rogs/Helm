import Core
import DesignSystem
import SwiftUI

/// Text-first food logging: describe the meal in plain language and the coach
/// estimates macros through the same `food_log.v1` pipeline chat dictation uses.
/// Search remains one tap away for offline or precision logging.
struct DescribeFoodSheet: View {
    let bucket: MealBucket
    @Binding var text: String
    let isEstimating: Bool
    let progressTitle: String
    let completedSteps: [String]
    let progressStep: String
    let errorMessage: String?
    let onSubmit: (String) -> Void
    let onUseSearch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    TextField(
                        "Two eggs on toast, splash of olive oil…",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(2...)
                    .focused($isFieldFocused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .disabled(isEstimating)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))

                    Text("The coach estimates calories and macros. You confirm before anything is logged.")
                        .helmType(.body, color: HelmColor.fgMuted)

                    if isEstimating {
                        CoachAIProgressCard(
                            eyebrow: "COACH",
                            title: progressTitle,
                            completedSteps: completedSteps,
                            currentStep: progressStep,
                            isImpactful: true
                        )
                    } else if let errorMessage, !errorMessage.isEmpty {
                        HelmErrorState(
                            title: "Couldn't estimate that meal",
                            message: errorMessage,
                            retryTitle: "Try again",
                            onRetry: submit
                        )
                    }

                    Button {
                        submit()
                    } label: {
                        Text(isEstimating ? "Estimating…" : "Estimate")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(trimmed.isEmpty || isEstimating)

                    Button("Search instead", action: onUseSearch)
                        .buttonStyle(.plain)
                        .foregroundStyle(HelmColor.fgSecondary)
                    .frame(maxWidth: .infinity, minHeight: HelmLayout.minTapTarget)
                        .disabled(isEstimating)
                }
                .padding(HelmSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .helmScreenBackground()
            .navigationTitle("Describe \(bucket.displayName.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .disabled(isEstimating)
                }
            }
            .onAppear { isFieldFocused = true }
            .interactiveDismissDisabled(isEstimating)
        }
    }

    private func submit() {
        guard !trimmed.isEmpty, !isEstimating else { return }
        isFieldFocused = false
        onSubmit(trimmed)
    }
}

#Preview("Describe food") {
    DescribeFoodSheet(
        bucket: .lunch,
        text: .constant(""),
        isEstimating: false,
        progressTitle: "Estimating meal",
        completedSteps: [],
        progressStep: "Estimating your meal…",
        errorMessage: nil,
        onSubmit: { _ in },
        onUseSearch: {}
    )
    .helmTheme()
}
