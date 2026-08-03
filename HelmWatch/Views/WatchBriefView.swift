import Core
import SwiftUI

struct WatchBriefView: View {
    let coordinator: WatchSessionCoordinator

    var body: some View {
        List {
            Section("Today's ARC") {
                if let score = coordinator.latestReadinessScore {
                    Text("\(score)")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if let band = coordinator.latestReadinessBand {
                        Text(band.capitalized)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Waiting for phone")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Morning brief") {
                if let summary = coordinator.latestBriefSummary {
                    Text(summary)
                } else {
                    Text("Open Signal on iPhone for your full brief.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Brief")
    }
}

#Preview {
    WatchBriefView(coordinator: WatchSessionCoordinator(role: .watch))
}
