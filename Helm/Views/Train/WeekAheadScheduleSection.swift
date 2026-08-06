import DesignSystem
import SwiftUI

struct WeekAheadScheduleSection: View {
    @Bindable var store: WeekAheadScheduleStore
    var onRegenerate: (() -> Void)?
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
            .onAppear {
                syncExpansion(for: model)
            }
            .onChange(of: store.model) { _, model in
                guard let model else { return }
                syncExpansion(for: model)
            }
        } else if !store.isLoading {
            emptyState
        }
    }

    private func syncExpansion(for model: WeekAheadScheduleModel) {
        guard model.chronologicalRows.contains(where: { $0.isToday && $0.busyDayHint != nil }) else { return }
        isExpanded = true
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
                        .lineLimit(2)
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

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Week ahead")
                    .helmType(.title)
                Text("Regenerate today's prescription to build your training schedule.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                if let onRegenerate {
                    Button("Regenerate plan", action: onRegenerate)
                        .buttonStyle(.helmSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var calendarPermissionBanner: some View {
        switch store.calendarAuthorizationStatus {
        case .notDetermined:
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text("Busy days")
                    .helmType(.label)
                Text("Connect your calendar so busy days shape training and rest.")
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
                Text("Enable calendar access in Settings so the plan can avoid busy days.")
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
