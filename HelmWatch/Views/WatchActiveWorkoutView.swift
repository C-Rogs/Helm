import Core
import SwiftUI

struct WatchActiveWorkoutView: View {
    @Bindable var store: WatchWorkoutSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            Text(store.selectedActivity.displayName)
                .font(WatchType.monoTag.font)
                .foregroundStyle(WatchPalette.fgMuted)

            Text(elapsedLabel)
                .watchType(.bigNumber)
                .accessibilityLabel("Elapsed \(elapsedLabel)")

            heartRateSection

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(store.phase == .paused ? "Resume" : "Pause") {
                    Task { await store.togglePause() }
                }
                .buttonStyle(.bordered)
                .tint(WatchPalette.fgSecondary)

                Button("End") {
                    Task { await store.endWorkout(discard: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchPalette.accent)
                .foregroundStyle(WatchPalette.buttonPrimaryForeground)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var heartRateSection: some View {
        if store.phase == .active || store.phase == .paused {
            let zone = store.heartRateZone
            let state = zone.map(WatchState.heartRateZone) ?? .ready
            let bpm = store.heartRateBPM.map { Int($0.rounded()) }

            WatchArcGauge(
                value: WatchZoneColor.progress(for: zone),
                state: state
            ) {
                VStack(spacing: 1) {
                    if let bpm {
                        Text("\(bpm)")
                            .watchType(.heroNumber, color: WatchZoneColor.color(for: zone))
                    } else {
                        Text("--")
                            .watchType(.heroNumber, color: WatchPalette.fgSecondary)
                    }
                    Text(zone?.displayName ?? "HR")
                        .watchType(.monoTag, color: WatchPalette.fgMuted)
                }
            }
            .frame(height: 96)
            .animation(
                WatchMotion.animation(WatchMotion.standardAnimation, reduceMotion: reduceMotion),
                value: zone
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hrAccessibilityLabel(bpm: bpm, zone: zone))
        }
    }

    private func hrAccessibilityLabel(bpm: Int?, zone: HeartRateZone?) -> String {
        let rate = bpm.map { "\($0) BPM" } ?? "No heart rate"
        if let zone {
            return "\(rate), \(zone.displayName)"
        }
        return rate
    }

    private var elapsedLabel: String {
        let minutes = store.elapsedSeconds / 60
        let seconds = store.elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
