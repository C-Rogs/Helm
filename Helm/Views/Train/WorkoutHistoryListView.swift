import Core
import DesignSystem
import SwiftUI

struct WorkoutHistoryListView: View {
    @Bindable var history: WorkoutHistoryController

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("History")
                .font(HelmTypography.headline)
                .foregroundStyle(HelmColor.textPrimary)

            if history.sessions.isEmpty {
                Text("No completed workouts yet.")
                    .font(HelmTypography.callout)
                    .foregroundStyle(HelmColor.textSecondary)
            } else {
                ForEach(history.sessions) { session in
                    NavigationLink {
                        WorkoutSessionDetailView(sessionID: session.id, history: history)
                    } label: {
                        WorkoutHistoryRow(summary: session)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        history.loadMoreIfNeeded(currentSessionID: session.id)
                    }
                }
            }
        }
    }
}

private struct WorkoutHistoryRow: View {
    let summary: WorkoutSessionSummary

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text(summary.title ?? "Workout")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.textPrimary)
                Text(summary.startedAt, style: .date)
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.textSecondary)
                HStack(spacing: HelmSpacing.md) {
                    Label("\(summary.totalSetCount) sets", systemImage: "checkmark.circle")
                    Label(String(format: "%.0f kg", summary.totalVolumeKilograms), systemImage: "scalemass")
                }
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutHistoryListView(history: TrainBootstrap.historyController)
            .helmTheme()
            .padding()
    }
}
