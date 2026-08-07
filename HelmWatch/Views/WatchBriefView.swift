import Core
import SwiftUI

struct WatchBriefView: View {
    let coordinator: WatchSessionCoordinator

    var body: some View {
        List {
            Section("Today's ARC") {
                if let score = coordinator.latestReadinessScore {
                    VStack(spacing: 2) {
                        Text("\(score)")
                            .font(WatchType.heroNumber.font)
                            .foregroundStyle(WatchReadinessBand.color(for: score))
                        if let band = coordinator.latestReadinessBand {
                            Text(band.capitalized)
                                .font(WatchType.monoTag.font)
                                .foregroundStyle(WatchPalette.fgSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                } else {
                    Text("Waiting for phone")
                        .font(WatchType.body.font)
                        .foregroundStyle(WatchPalette.fgSecondary)
                }
            }
            .listRowBackground(WatchPalette.surface)

            Section("Morning brief") {
                if let summary = coordinator.latestBriefSummary {
                    Text(summary)
                        .font(WatchType.body.font)
                        .foregroundStyle(WatchPalette.fg)
                } else {
                    Text("Open Signal on iPhone for your full brief.")
                        .font(WatchType.body.font)
                        .foregroundStyle(WatchPalette.fgSecondary)
                }
            }
            .listRowBackground(WatchPalette.surface)
        }
        .navigationTitle("Brief")
        .helmWatchScreenBackground()
    }
}

#Preview {
    WatchBriefView(coordinator: WatchSessionCoordinator(role: .watch))
        .helmWatchTheme()
}