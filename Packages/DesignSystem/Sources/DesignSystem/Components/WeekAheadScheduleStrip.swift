import SwiftUI

public struct WeekAheadScheduleStrip: View {
    private let model: WeekAheadScheduleModel
    private let cardMinWidth: CGFloat = 112

    public init(model: WeekAheadScheduleModel) {
        self.model = model
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HelmSpacing.xs) {
                    ForEach(model.chronologicalRows) { row in
                        dayCard(for: row)
                            .id(row.id)
                    }
                }
                .padding(.vertical, HelmSpacing.xxs)
            }
            .onAppear {
                scrollToToday(using: proxy)
            }
            .onChange(of: model.chronologicalRows.map(\.id)) { _, _ in
                scrollToToday(using: proxy)
            }
        }
    }

    private func scrollToToday(using proxy: ScrollViewProxy) {
        guard let todayID = model.chronologicalRows.first(where: \.isToday)?.id else { return }
        proxy.scrollTo(todayID, anchor: .leading)
    }

    private func dayCard(for row: WeekAheadScheduleRow) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(row.dayLabel)
                .helmType(.monoTag, color: row.isToday ? HelmColor.accent : HelmColor.fgMuted)
                .lineLimit(1)
            Text(row.splitLabel)
                .helmType(.label)
                .foregroundStyle(row.isRestDay ? HelmColor.fgSecondary : HelmColor.fg)
                .lineLimit(1)
            if let busyDayHint = row.busyDayHint {
                Text(busyDayHint)
                    .helmType(.monoTag, color: HelmColor.compromised)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let statusLabel = row.statusLabel {
                Text(statusLabel)
                    .helmType(.monoTag, color: statusColor(for: row.status))
                    .lineLimit(1)
            } else {
                Text(" ")
                    .helmType(.monoTag, color: .clear)
            }
        }
        .frame(minWidth: cardMinWidth, alignment: .leading)
        .padding(.horizontal, HelmSpacing.sm)
        .padding(.vertical, HelmSpacing.sm)
        .background(cardBackground(for: row))
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.sm, style: .continuous)
                .stroke(borderColor(for: row), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func cardBackground(for row: WeekAheadScheduleRow) -> Color {
        if row.isToday {
            return HelmColor.accent.opacity(0.12)
        }
        if row.isRestDay {
            return HelmColor.surface.opacity(0.55)
        }
        return HelmColor.surface
    }

    private func borderColor(for row: WeekAheadScheduleRow) -> Color {
        if row.busyDayHint != nil {
            return HelmColor.compromised.opacity(0.45)
        }
        if row.isToday {
            return HelmColor.accent.opacity(0.35)
        }
        return HelmColor.hairline
    }

    private func statusColor(for status: WeekAheadSessionStatus) -> Color {
        switch status {
        case .completed:
            HelmColor.ready
        case .missed, .skipped:
            HelmColor.depleted
        case .shifted:
            HelmColor.compromised
        case .rest:
            HelmColor.fgMuted
        case .today, .upcoming:
            HelmColor.fgMuted
        }
    }

    private func accessibilityLabel(for row: WeekAheadScheduleRow) -> String {
        var parts = [row.dayLabel, row.splitLabel]
        if let statusLabel = row.statusLabel {
            parts.append(statusLabel)
        }
        if let busyDayHint = row.busyDayHint {
            parts.append(busyDayHint)
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
