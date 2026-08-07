import Core
import SwiftUI

struct WatchActiveWorkoutView: View {
    @Bindable var store: WatchWorkoutSessionStore

    var body: some View {
        VStack(spacing: 6) {
            Text(store.selectedActivity.displayName)
                .font(WatchType.monoTag.font)
                .foregroundStyle(WatchPalette.fgMuted)

            Text(elapsedLabel)
                .font(WatchType.bigNumber.font)
                .foregroundStyle(WatchPalette.fg)

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
            VStack(spacing: 2) {
                if let bpm = store.heartRateBPM {
                    Text("\(Int(bpm.rounded()))")
                        .font(WatchType.heroNumber.font)
                        .foregroundStyle(WatchZoneColor.color(for: store.heartRateZone))
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(WatchZoneColor.color(for: store.heartRateZone))
                    if let zone = store.heartRateZone {
                        Text(zone.displayName)
                            .font(WatchType.monoTag.font)
                            .foregroundStyle(WatchZoneColor.color(for: store.heartRateZone))
                    }
                } else {
                    Text("--")
                        .font(WatchType.heroNumber.font)
                        .foregroundStyle(WatchPalette.fgSecondary)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(WatchPalette.fgMuted)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var elapsedLabel: String {
        let minutes = store.elapsedSeconds / 60
        let seconds = store.elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}