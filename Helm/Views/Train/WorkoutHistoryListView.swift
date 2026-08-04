import Core
import DesignSystem
import SwiftUI

struct WorkoutHistoryListView: View {
    @Bindable var history: WorkoutHistoryController
    @Namespace private var cardNamespace
    @State private var pendingDeleteSessionID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HelmSectionEyebrow("HISTORY", showsArcMark: false)

            if let errorMessage = history.errorMessage {
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
                ForEach(Array(history.sessions.enumerated()), id: \.element.id) { index, session in
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
}

private struct WorkoutHistoryRow: View {
    let summary: WorkoutSessionSummary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text(summary.title ?? "Workout")
                    .helmType(.label)
                Text(summary.startedAt, style: .date)
                    .helmType(.body, color: HelmColor.fgSecondary)
                HStack(spacing: HelmSpacing.md) {
                    Label {
                        HStack(spacing: HelmSpacing.xxs) {
                            HelmNumericText(summary.totalSetCount)
                            Text("sets")
                                .helmType(.body, color: HelmColor.fgSecondary)
                        }
                    } icon: {
                        HelmIconView(.checkmark, context: .inline)
                    }
                    Label {
                        HStack(spacing: HelmSpacing.xxs) {
                            HelmNumericText(summary.totalVolumeKilograms, format: "%.0f")
                            Text("kg")
                                .helmType(.body, color: HelmColor.fgSecondary)
                        }
                    } icon: {
                        HelmIconView(.scale, context: .inline)
                    }
                }
                .foregroundStyle(HelmColor.fgSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("History empty") {
    NavigationStack {
        HelmEmptyState(
            title: "No workouts yet",
            message: "Finish a session to see it here.",
            icon: .train
        )
        .helmTheme()
        .padding()
    }
}

#Preview("History error") {
    NavigationStack {
        HelmErrorState(
            title: "History unavailable",
            message: "Could not load workout history.",
            onRetry: {}
        )
        .helmTheme()
        .padding()
    }
}

#Preview {
    NavigationStack {
        WorkoutHistoryListView(history: TrainBootstrap.historyController)
            .helmTheme()
            .padding()
    }
}
