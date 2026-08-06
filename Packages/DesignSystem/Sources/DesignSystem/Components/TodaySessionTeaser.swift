import SwiftUI

/// Compact Dashboard glance for today's prescribed session. Controls live on Train.
public struct TodaySessionTeaser: View {
    public let title: String
    public let totalSets: Int
    public let phaseLabel: String?
    public let readinessAdjusted: Bool
    public let onOpenTrain: () -> Void

    public init(
        title: String,
        totalSets: Int,
        phaseLabel: String? = nil,
        readinessAdjusted: Bool = false,
        onOpenTrain: @escaping () -> Void
    ) {
        self.title = title
        self.totalSets = totalSets
        self.phaseLabel = phaseLabel
        self.readinessAdjusted = readinessAdjusted
        self.onOpenTrain = onOpenTrain
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("TODAY'S SESSION")

                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.sm) {
                    Text(title)
                        .helmType(.title)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let phaseLabel {
                        Text(phaseLabel)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }

                HStack(spacing: HelmSpacing.xxs) {
                    HelmNumericText(totalSets)
                    Text("total sets")
                        .helmType(.body, color: HelmColor.fgSecondary)
                }

                if readinessAdjusted {
                    Text("Volume trimmed for readiness")
                        .helmType(.monoTag, color: HelmColor.depleted)
                }

                Button("Open Train", action: onOpenTrain)
                    .buttonStyle(.helmPrimary)
            }
        }
    }
}

#Preview("Today session teaser") {
    TodaySessionTeaser(
        title: "Pull",
        totalSets: 16,
        phaseLabel: "Accumulate",
        readinessAdjusted: true,
        onOpenTrain: {}
    )
    .padding()
    .helmTheme()
}

#Preview("Today session teaser plain") {
    TodaySessionTeaser(
        title: "Push",
        totalSets: 14,
        phaseLabel: "Accumulate",
        onOpenTrain: {}
    )
    .padding()
    .helmTheme()
}
