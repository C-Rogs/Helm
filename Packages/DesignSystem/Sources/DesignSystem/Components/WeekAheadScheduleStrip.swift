import SwiftUI

public struct WeekAheadScheduleStrip: View {
    private let model: WeekAheadScheduleModel

    public init(model: WeekAheadScheduleModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HelmSpacing.xs) {
                ForEach(model.rows) { row in
                    pill(for: row)
                }
            }
            .padding(.vertical, HelmSpacing.xxs)
        }
    }

    private func pill(for row: WeekAheadScheduleRow) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(row.dayLabel)
                .helmType(.monoTag, color: row.isToday ? HelmColor.accent : HelmColor.fgMuted)
            Text(row.splitLabel)
                .helmType(.label)
            if let statusLabel = row.statusLabel {
                Text(statusLabel)
                    .helmType(.monoTag, color: statusColor(for: row.status))
            }
        }
        .padding(.horizontal, HelmSpacing.sm)
        .padding(.vertical, HelmSpacing.xs)
        .background(row.isToday ? HelmColor.accent.opacity(0.12) : HelmColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.sm, style: .continuous)
                .stroke(row.isToday ? HelmColor.accent.opacity(0.35) : HelmColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func statusColor(for status: WeekAheadSessionStatus) -> Color {
        switch status {
        case .completed:
            HelmColor.ready
        case .missed, .skipped:
            HelmColor.depleted
        case .shifted:
            HelmColor.compromised
        case .today, .upcoming:
            HelmColor.fgMuted
        }
    }

    private func accessibilityLabel(for row: WeekAheadScheduleRow) -> String {
        var parts = [row.dayLabel, row.splitLabel]
        if let statusLabel = row.statusLabel {
            parts.append(statusLabel)
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Week ahead strip") {
    WeekAheadScheduleStrip(model: .weekAheadFixture)
        .padding()
        .helmTheme()
}
#endif
