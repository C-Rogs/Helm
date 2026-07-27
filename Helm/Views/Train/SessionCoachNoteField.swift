import DesignSystem
import SwiftUI

struct SessionCoachNoteField: View {
    @Binding var text: String
    let onTextChange: (String) -> Void
    let onSaveToMemory: () -> Void
    let savedConfirmation: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Button {
                withAnimation(HelmMotion.settleAnimation) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label("Note for coach", systemImage: "note.text")
                        .helmType(.label, color: HelmColor.fg)
                    Spacer()
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Active")
                            .helmType(.monoTag, color: HelmColor.accent)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(HelmColor.fgMuted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                TextField(
                    "Injuries, equipment, swaps…",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(2 ... 5)
                .textFieldStyle(.plain)
                .padding(HelmSpacing.sm)
                .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                .onChange(of: text) { _, newValue in
                    onTextChange(newValue)
                }

                HStack(spacing: HelmSpacing.sm) {
                    Button("Save to memory") {
                        onSaveToMemory()
                    }
                    .buttonStyle(.helmSecondary)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if savedConfirmation {
                        Text("Saved to Coach Memory")
                            .helmType(.monoTag, color: HelmColor.accent)
                    }
                }
            }
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(HelmColor.hairline, lineWidth: 1)
        }
    }
}
