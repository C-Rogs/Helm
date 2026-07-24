import Core
import DesignSystem
import SwiftUI

struct WorkoutHistoryListView: View {
    @Bindable var history: WorkoutHistoryController
    @Namespace private var cardNamespace

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
                    .buttonStyle(.plain)
                    .helmStaggeredAppear(index: index)
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
                    Label {
                        HStack(spacing: HelmSpacing.xxs) {
                            HelmNumericText(summary.totalSetCount)
                            Text("sets")
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                    Label {
                        HStack(spacing: HelmSpacing.xxs) {
                            HelmNumericText(summary.totalVolumeKilograms, format: "%.0f")
                            Text("kg")
                        }
                    } icon: {
                        Image(systemName: "scalemass")
                    }
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
