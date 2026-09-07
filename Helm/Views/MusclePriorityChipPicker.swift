import DesignSystem
import PlanKit
import SwiftUI

/// Multi-select chips for 1…3 focus muscles. Instrument chrome; no essay field.
struct MusclePriorityChipPicker: View {
    @Binding var selected: [MuscleGroup]
    var maxSelection: Int = MusclePriorityRedistribution.maxPriorities

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: HelmSpacing.xs)],
                alignment: .leading,
                spacing: HelmSpacing.xs
            ) {
                ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                    chip(for: muscle)
                }
            }
            Text(footerCopy)
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.fgMuted)
        }
    }

    private var footerCopy: String {
        if selected.isEmpty {
            return "Pick up to \(maxSelection) muscles. Weekly hard-set targets shift toward them."
        }
        let names = selected.map(\.displayLabel).joined(separator: " · ")
        return "Focus: \(names). Clear chips to restore even volume."
    }

    private func chip(for muscle: MuscleGroup) -> some View {
        let isOn = selected.contains(muscle)
        return Button {
            toggle(muscle)
        } label: {
            Text(muscle.displayLabel)
                .helmType(.monoTag, color: isOn ? HelmColor.fg : HelmColor.fgSecondary)
                .padding(.horizontal, HelmSpacing.sm)
                .padding(.vertical, HelmSpacing.xs)
                .frame(maxWidth: .infinity)
                .background(
                    isOn ? HelmColor.accent.opacity(0.22) : HelmColor.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: HelmRadius.sm)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: HelmRadius.sm)
                        .strokeBorder(isOn ? HelmColor.accent.opacity(0.55) : HelmColor.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(muscle.displayLabel)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggle(_ muscle: MuscleGroup) {
        HapticEngine.shared.play(.selection)
        if let index = selected.firstIndex(of: muscle) {
            selected.remove(at: index)
            return
        }
        guard selected.count < maxSelection else { return }
        selected.append(muscle)
    }
}
