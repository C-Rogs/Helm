import SwiftUI

/// One selectable answer row for `MultipleChoiceQuestionView`.
public struct MCQOption: Identifiable, Hashable {
    public let id: String
    public let label: String
    public let detail: String?

    public init(id: String, label: String, detail: String? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}

/// Helm-styled single- or multi-select question block with selection haptics.
public struct MultipleChoiceQuestionView: View {
    let question: String
    let options: [MCQOption]
    let allowsMultiple: Bool
    @Binding var selectedIDs: Set<String>

    public init(
        question: String,
        options: [MCQOption],
        allowsMultiple: Bool = false,
        selection: Binding<Set<String>>
    ) {
        self.question = question
        self.options = options
        self.allowsMultiple = allowsMultiple
        _selectedIDs = selection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text(question)
                .helmType(.title, color: HelmColor.fg)

            ForEach(options) { option in
                optionRow(option)
            }
        }
    }

    private func optionRow(_ option: MCQOption) -> some View {
        let isSelected = selectedIDs.contains(option.id)
        return Button {
            HapticEngine.shared.play(.selection)
            if isSelected {
                if allowsMultiple {
                    selectedIDs.remove(option.id)
                } else if selectedIDs != [option.id] {
                    selectedIDs = [option.id]
                }
            } else {
                if !allowsMultiple {
                    selectedIDs = []
                }
                selectedIDs.insert(option.id)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.sm) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? HelmColor.accent : HelmColor.fgMuted)

                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text(option.label)
                        .helmType(.body, color: HelmColor.fg)
                    if let detail = option.detail {
                        Text(detail)
                            .helmType(.label, color: HelmColor.fgMuted)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(HelmSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.md)
                    .strokeBorder(
                        isSelected ? HelmColor.accent : HelmColor.hairline,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Single select") {
    MultipleChoiceQuestionView(
        question: "How many days can you train?",
        options: [
            MCQOption(id: "3", label: "Three days"),
            MCQOption(id: "4", label: "Four days", detail: "Most flexible for PPL rotations")
        ],
        selection: .constant(["3"])
    )
    .padding()
    .helmTheme()
    .helmScreenBackground()
}
