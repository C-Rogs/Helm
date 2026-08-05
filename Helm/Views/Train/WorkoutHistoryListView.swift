import Core
import DesignSystem
import SwiftUI

private enum WorkoutHistoryPresentation {
    static let recentPreviewLimit = 3
}

struct WorkoutHistoryRecentSection: View {
    @Bindable var history: WorkoutHistoryController
    @Namespace private var cardNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            sectionHeader

            if history.loadState == .loadingInitial, history.sessions.isEmpty {
                HelmLoadingState(rowCount: 2)
            } else if let errorMessage = history.errorMessage, history.sessions.isEmpty {
                HelmErrorState(
                    title: "History unavailable",
                    message: errorMessage,
                    onRetry: { history.refresh() }
                )
            } else if history.sessions.isEmpty {
                Text("Finish a session to see it here.")
                    .helmType(.body, color: HelmColor.fgSecondary)
            } else {
                ForEach(Array(recentSessions.enumerated()), id: \.element.id) { index, session in
                    historyNavigationLink(for: session, staggerIndex: index)
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.sm) {
            Text("Recent workouts")
                .helmType(.label)

            Spacer(minLength: HelmSpacing.sm)

            if !history.sessions.isEmpty {
                NavigationLink {
                    WorkoutHistoryScreen(history: history)
                } label: {
                    Text("View all")
                        .helmType(.monoTag, color: HelmColor.accent)
                        .frame(minHeight: 44, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all workout history")
            }
        }
    }

    private var recentSessions: [WorkoutSessionSummary] {
        Array(history.sessions.prefix(WorkoutHistoryPresentation.recentPreviewLimit))
    }

    @ViewBuilder
    private func historyNavigationLink(for session: WorkoutSessionSummary, staggerIndex: Int) -> some View {
        NavigationLink {
            WorkoutSessionDetailView(
                sessionID: session.id,
                history: history,
                matchedCardNamespace: cardNamespace
            )
        } label: {
            WorkoutHistoryRow(summary: session)
                .helmMatchedCardDetail(id: session.id, in: cardNamespace)
        }
        .buttonStyle(.helmPressableCard)
        .helmStaggeredAppear(index: staggerIndex)
    }
}

struct WorkoutHistoryScreen: View {
    @Bindable var history: WorkoutHistoryController
    @Namespace private var cardNamespace
    @State private var pendingDeleteSessionID: String?

    private var monthSections: [WorkoutHistoryMonthSection] {
        WorkoutHistoryFormatting.groupByMonth(history.sessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                if history.loadState == .loadingInitial, history.sessions.isEmpty {
                    HelmLoadingState(rowCount: 4)
                } else if let errorMessage = history.errorMessage, history.sessions.isEmpty {
                    HelmErrorState(
                        title: "History unavailable",
                        message: errorMessage,
                        onRetry: { history.refresh() }
                    )
                } else if history.sessions.isEmpty {
                    HelmEmptyState(
                        title: "No workouts yet",
                        message: "Finish a session to see it here.",
                        icon: .train
                    )
                } else {
                    ForEach(monthSections) { section in
                        monthSection(section)
                    }

                    if history.loadState == .loadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, HelmSpacing.sm)
                            .accessibilityLabel("Loading more workouts")
                    }
                }
            }
            .helmScreenPadding()
            .padding(.bottom, HelmLayout.trainScrollBottomInset)
        }
        .helmScreenBackground()
        .navigationTitle("Workout history")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            history.refresh()
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(
                get: { pendingDeleteSessionID != nil },
                set: { if !$0 { pendingDeleteSessionID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete workout", role: .destructive) {
                if let id = pendingDeleteSessionID {
                    history.deleteSession(id: id)
                }
                pendingDeleteSessionID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteSessionID = nil
            }
        } message: {
            Text("Removes it from history. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func monthSection(_ section: WorkoutHistoryMonthSection) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text(section.title.uppercased())
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(section.sessions.enumerated()), id: \.element.id) { index, session in
                NavigationLink {
                    WorkoutSessionDetailView(
                        sessionID: session.id,
                        history: history,
                        matchedCardNamespace: cardNamespace
                    )
                } label: {
                    WorkoutHistoryRow(summary: session)
                        .helmMatchedCardDetail(id: session.id, in: cardNamespace)
                }
                .buttonStyle(.helmPressableCard)
                .contextMenu {
                    Button("Delete workout", role: .destructive) {
                        pendingDeleteSessionID = session.id
                    }
                }
                .helmStaggeredAppear(index: index)
                .onAppear {
                    history.loadMoreIfNeeded(currentSessionID: session.id)
                }
            }
        }
    }
}

struct WorkoutHistoryRow: View {
    let summary: WorkoutSessionSummary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text(summary.title ?? "Workout")
                        .helmType(.label)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(WorkoutHistoryFormatting.contextualDateTimeLabel(summary.startedAt))
                        .helmType(.body, color: HelmColor.fgSecondary)
                }

                HStack(spacing: HelmSpacing.md) {
                    if let duration = WorkoutHistoryFormatting.durationLabel(
                        startedAt: summary.startedAt,
                        endedAt: summary.endedAt
                    ) {
                        Text(duration)
                            .helmType(.monoTag, color: HelmColor.fgSecondary)
                    }
                    metricChip(icon: .train, value: "\(summary.exerciseCount)", unit: "ex")
                    metricChip(icon: .checkmark, value: "\(summary.totalSetCount)", unit: "sets")
                    metricChip(
                        icon: .scale,
                        value: WorkoutHistoryFormatting.volumeLabel(kilograms: summary.totalVolumeKilograms),
                        unit: "kg"
                    )
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WorkoutHistoryFormatting.accessibilityLabel(for: summary))
        .accessibilityAddTraits(.isButton)
    }

    private func metricChip(icon: HelmIcon, value: String, unit: String?) -> some View {
        HStack(spacing: HelmSpacing.xxs) {
            HelmIconView(icon, context: .inline)
                .foregroundStyle(HelmColor.fgMuted)
                .frame(width: 16, alignment: .center)
            Text(value)
                .helmType(.number, color: HelmColor.fgSecondary)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Recent section empty") {
    NavigationStack {
        WorkoutHistoryRecentSection(history: TrainBootstrap.historyController)
            .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Recent section loading") {
    NavigationStack {
        WorkoutHistoryRecentSection(history: TrainBootstrap.historyController)
            .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("History screen empty") {
    NavigationStack {
        WorkoutHistoryScreen(history: TrainBootstrap.historyController)
    }
    .helmTheme()
}

#Preview("History screen error") {
    NavigationStack {
        HelmErrorState(
            title: "History unavailable",
            message: "Could not load workout history.",
            onRetry: {}
        )
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("History row") {
    WorkoutHistoryRow(
        summary: WorkoutSessionSummary(
            id: "preview",
            title: "Push Day",
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(3_240),
            totalVolumeKilograms: 6_420,
            totalSetCount: 16,
            totalRepCount: 80,
            exerciseCount: 5
        )
    )
    .helmScreenPadding()
    .helmTheme()
}

#Preview("History row accessibility") {
    WorkoutHistoryRow(
        summary: WorkoutSessionSummary(
            id: "preview",
            title: "Push Day",
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(3_240),
            totalVolumeKilograms: 6_420,
            totalSetCount: 16,
            totalRepCount: 80,
            exerciseCount: 5
        )
    )
    .helmScreenPadding()
    .helmTheme()
    .dynamicTypeSize(.accessibility3)
}
