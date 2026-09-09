import DesignSystem
import SwiftUI

struct ProgressHistoryWindowPicker: View {
    @Binding var window: TrendsHistoryWindow

    var body: some View {
        HStack(spacing: HelmSpacing.xxs) {
            ForEach(TrendsHistoryWindow.allCases) { candidate in
                let selected = window == candidate
                Button {
                    window = candidate
                } label: {
                    Text(candidate.label)
                        .helmType(.monoTag, color: selected ? HelmColor.accent : HelmColor.fgMuted)
                        .padding(.horizontal, HelmSpacing.xs)
                        .padding(.vertical, HelmSpacing.xxs)
                        .background(
                            selected ? HelmColor.accent.opacity(0.12) : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(selected ? HelmColor.accent.opacity(0.35) : HelmColor.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
