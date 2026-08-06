import SwiftUI

public struct WeekAheadScheduleView: View {
    private let model: WeekAheadScheduleModel
    private let showsHeader: Bool

    public init(model: WeekAheadScheduleModel, showsHeader: Bool = true) {
        self.model = model
        self.showsHeader = showsHeader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            if showsHeader {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text("Week ahead")
                        .helmType(.title)
                    Text("Planned training and rest days for the next week")
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            }

            if model.rows.isEmpty {
                Text("Regenerate today's prescription to populate the week schedule.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .frame(maxWidth: .infinity, minHeight: HelmLayout.emptyChartMinHeight, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.chronologicalRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            HelmHairlineRule()
                        }
                        rowView(row)
                            .padding(.vertical, HelmSpacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: WeekAheadScheduleRow) -> some View {
        HStack(alignment: .top, spacing: HelmSpacing.sm) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(row.dayLabel)
                    .helmType(row.isToday ? .label : .body, color: row.isToday ? HelmColor.accent : HelmColor.fgSecondary)
                if let note = row.note {
                    Text(note)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
                if let busyDayHint = row.busyDayHint {
                    Text(busyDayHint)
                        .helmType(.monoTag, color: HelmColor.compromised)
                }
            }

            Spacer(minLength: HelmSpacing.sm)

            VStack(alignment: .trailing, spacing: HelmSpacing.xxs) {
                Text(row.splitLabel)
                    .helmType(.label)
                if let statusLabel = row.statusLabel {
                    Text(statusLabel)
                        .helmType(.monoTag, color: statusColor(for: row.status))
                }
                if let driftNote = row.driftNote {
                    Text(driftNote)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        if let driftNote = row.driftNote {
            parts.append(driftNote)
        }
        if let note = row.note {
            parts.append(note)
        }
        if let busyDayHint = row.busyDayHint {
            parts.append(busyDayHint)
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Week ahead instrument") {
    Card {
        WeekAheadScheduleView(model: .weekAheadFixture)
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("Week ahead data sheet") {
    Card {
        WeekAheadScheduleView(model: .weekAheadFixture)
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}

#Preview("Week ahead drift") {
    Card {
        WeekAheadScheduleView(model: .driftScenarioFixture)
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("Week ahead busy day") {
    Card {
        WeekAheadScheduleView(model: .busyDayFixture)
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("Week ahead empty") {
    Card {
        WeekAheadScheduleView(model: WeekAheadScheduleModel(rows: []))
    }
    .padding()
    .helmTheme()
}
#endif
