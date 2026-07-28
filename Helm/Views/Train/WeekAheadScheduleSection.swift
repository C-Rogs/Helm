import DesignSystem
import SwiftUI

struct WeekAheadScheduleSection: View {
    @Bindable var store: WeekAheadScheduleStore

    var body: some View {
        if store.isLoading, store.model == nil {
            HelmSkeletonCard(rowCount: 3)
        } else if let model = store.model, !model.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    if store.calendarAuthorizationStatus != .authorized {
                        calendarPermissionBanner
                    }
                    WeekAheadScheduleView(model: model, showsHeader: true)
                }
            }
        }
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
