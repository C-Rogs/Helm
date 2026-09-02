import Core
import SwiftUI

struct WatchActiveWorkoutView: View {
    @Bindable var store: WatchWorkoutSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: WatchSpacing.xxs + 2) {
            if !isLuminanceReduced {
                Text(store.selectedActivity.displayName)
                    .font(WatchType.monoTag.font)
                    .foregroundStyle(WatchPalette.fgMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.trailing, WatchLayout.clockClearance)
            }

            heartRateSection

            if !isLuminanceReduced {
                elapsedReadout
            }

            Spacer(minLength: 0)

            if !isLuminanceReduced {
                HStack(spacing: WatchSpacing.xs) {
                    Button(store.phase == .paused ? "Resume" : "Pause") {
                        WatchHaptic.playPause(isPaused: store.phase == .paused)
                        Task { await store.togglePause() }
                    }
                    .buttonStyle(.bordered)
                    .tint(WatchPalette.fgSecondary)
                    .frame(minHeight: WatchLayout.hit)

                    Button("End") {
                        WatchHaptic.sessionEnd.play()
                        Task { await store.endWorkout(discard: false) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchPalette.accent)
                    .foregroundStyle(WatchPalette.buttonPrimaryForeground)
                    .frame(minHeight: WatchLayout.hit)
                }
            }
        }
        .padding(.horizontal, WatchSpacing.xs)
        .padding(.bottom, WatchSpacing.xxs + 2)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var elapsedReadout: some View {
        WatchRollingTime(
            seconds: store.elapsedSeconds,
            style: .number,
            color: WatchPalette.fgMuted
        )
        .accessibilityLabel("Elapsed \(WatchTimeFormatting.mmss(store.elapsedSeconds))")
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
                            .watchType(isLuminanceReduced ? .bigNumber : .heroNumber, color: WatchZoneColor.color(for: zone))
                            .watchNumericRoll(value: bpm, reduceMotion: reduceMotion)
                    } else {
                        Text("--")
                            .watchType(isLuminanceReduced ? .bigNumber : .heroNumber, color: WatchPalette.fgSecondary)
                    }
                    if !isLuminanceReduced {
                        WatchZoneCaption(zone: zone)
                    }
                }
            }
            .frame(height: isLuminanceReduced ? WatchLayout.heroArcAOD : WatchLayout.heroArc)
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
}
