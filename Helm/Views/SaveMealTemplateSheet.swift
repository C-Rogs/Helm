import Core
import DesignSystem
import SwiftUI

struct SaveMealTemplateSheet: View {
    let bucket: MealBucket
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                Text("Save today's \(bucket.displayName.lowercased()) as a template for one-tap logging.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text("Template name")
                        .helmType(.label)
                    TextField("e.g. Work breakfast", text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                        .helmType(.body)
                        .padding(HelmSpacing.sm)
                        .background(HelmColor.gaugeTrack.opacity(0.35), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                }

                Spacer()
            }
            .padding(HelmSpacing.md)
            .helmScreenBackground()
            .navigationTitle("Save template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview("Save template") {
    SaveMealTemplateSheet(
        bucket: .breakfast,
        onSave: { _ in },
        onCancel: {}
    )
    .helmTheme()
}
