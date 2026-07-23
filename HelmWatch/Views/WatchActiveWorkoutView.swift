import Core
import SwiftUI

struct WatchActiveWorkoutView: View {
    @Bindable var store: WatchWorkoutSessionStore

    var body: some View {
        VStack(spacing: 8) {
            Text(store.selectedActivity.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(elapsedLabel)
                .font(.title2.monospacedDigit())

            heartRateSection

            HStack {
                Button(store.phase == .paused ? "Resume" : "Pause") {
                    Task { await store.togglePause() }
                }
                .buttonStyle(.bordered)

                Button("End") {
                    Task { await store.endWorkout(discard: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var heartRateSection: some View {
        if store.phase == .active || store.phase == .paused {
            VStack(spacing: 4) {
                if let bpm = store.heartRateBPM {
                    Text("\(Int(bpm.rounded()))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(zoneColor)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let zone = store.heartRateZone {
                        Text(zone.displayName)
                            .font(.caption)
                            .foregroundStyle(zoneColor)
                    }
                } else {
                    Text("--")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private var elapsedLabel: String {
        let minutes = store.elapsedSeconds / 60
        let seconds = store.elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var zoneColor: Color {
        switch store.heartRateZone {
        case .zone1: .mint
        case .zone2: .blue
        case .zone3: .yellow
        case .zone4: .orange
        case .zone5: .red
        case nil: .primary
        }
    }
}
