import DesignSystem
import SwiftUI

struct WeekAheadScheduleSection: View {
    @Bindable var store: WeekAheadScheduleStore
    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    var body: some View {
        if store.isLoading, store.model == nil {
            HelmSkeletonCard(rowCount: 3)
        } else if let model = store.model, !model.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    header(for: model)

                    if store.calendarAuthorizationStatus != .authorized {
                        calendarPermissionBanner
                    }

                    if isExpanded {
                        WeekAheadScheduleView(model: model, showsHeader: false)
                    } else {
                        WeekAheadScheduleStrip(model: model)
                    }
                }
            }
        }
    }

    private func header(for model: WeekAheadScheduleModel) -> some View {
        Button {
            withAnimation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text("Week ahead")
                        .helmType(.title)
                    Text(model.collapsedSummary)
                        .helmType(.body, color: HelmColor.fgSecondary)
                }

                Spacer(minLength: HelmSpacing.sm)

                HelmIconView(isExpanded ? .chevronUp : .chevronDown, context: .inline)
                    .foregroundStyle(HelmColor.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse week ahead schedule" : "Expand week ahead schedule")
    }

    @ViewBuilder
    private var calendarPermissionBanner: some View {
        switch store.calendarAuthorizationStatus {
        case .notDetermined:
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text("Busy-day hints")
                    .helmType(.label)
                Text("Connect your calendar to flag packed days on this schedule.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                Button("Allow Calendar Access") {
                    Task { await store.requestCalendarAccess() }
                }
                .buttonStyle(.helmSecondary)
            }
            HelmHairlineRule()
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text("Calendar access off")
                    .helmType(.label)
                Text("Enable calendar access in Settings to surface busy-day hints.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                NavigationLink("Open Calendar Settings") {
                    CalendarHintStatusView()
                }
            }
            HelmHairlineRule()
        case .authorized:
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("Week ahead section") {
    ScrollView {
        WeekAheadScheduleSection(store: WeekAheadScheduleBootstrap.store)
            .helmScreenPadding()
    }
    .helmTheme()
}
#endif
