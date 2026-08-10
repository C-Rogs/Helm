import Core
import DesignSystem
import SwiftUI

/// Text-first food logging: describe the meal in plain language and the coach
/// estimates macros through the same `food_log.v1` pipeline chat dictation uses.
/// Search remains one tap away for offline or precision logging.
struct DescribeFoodSheet: View {
    let bucket: MealBucket
    @Binding var text: String
    let onSubmit: (String) -> Void
    let onUseSearch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFieldFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                TextField(
                    "Two eggs on toast, splash of olive oil…",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(2 ... 4)
                .focused($isFieldFocused)
                .submitLabel(.send)
                .onSubmit {
                    guard !trimmed.isEmpty else { return }
                    onSubmit(trimmed)
                }
                .padding(HelmSpacing.sm)
                .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))

                Text("The coach estimates calories and macros. You confirm before anything is logged.")
                    .helmType(.body, color: HelmColor.fgMuted)

                Button {
                    onSubmit(trimmed)
                } label: {
                    Text("Estimate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.helmPrimary)
                .disabled(trimmed.isEmpty)

                Button("Search instead", action: onUseSearch)
                    .buttonStyle(.plain)
                    .foregroundStyle(HelmColor.fgSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(HelmSpacing.md)
            .frame(maxHeight: .infinity, alignment: .top)
            .helmScreenBackground()
            .navigationTitle("Describe \(bucket.displayName.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isFieldFocused = true }
        }
    }
}

#Preview("Describe food") {
    DescribeFoodSheet(
        bucket: .lunch,
        text: .constant(""),
        onSubmit: { _ in },
        onUseSearch: {}
    )
    .helmTheme()
}
