import Core
import SwiftUI

struct WatchCompanionView: View {
    @Bindable var store: WatchWorkoutSessionStore
    let coordinator: WatchSessionCoordinator
    var onRetryStart: (() -> Void)?
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var restSpanSeconds: Double = 1
    @State private var restWindowEnd: TimeInterval?
    @State private var restDisplaySeconds: Int = 0

    var body: some View {
        VStack(spacing: WatchSpacing.xxs) {
            if !isLuminanceReduced {
                headerRow
                    .padding(.trailing, WatchLayout.clockClearance)
                exerciseBlock
                    .padding(.trailing, WatchLayout.clockClearance)
                elapsedReadout
            }

            hero

            if !isLuminanceReduced, isRestingNow {
                restChips
            }

            Spacer(minLength: 0)

            if !isLuminanceReduced, !isRestingNow {
                doneButton
                statusFooter
            }
        }
        .padding(.horizontal, WatchSpacing.xs)
        .padding(.bottom, WatchSpacing.xxs)
        .frame(maxHeight: .infinity)
        .background { restClock }
        .onAppear {
            captureRestSpan(coordinator.companionRestEndsAt)
            syncRestDisplay(at: Date(), animated: false)
            coordinator.tickRestHaptics(at: Date())
        }
        .onChange(of: coordinator.companionRestEndsAt) { _, newEnds in
            captureRestSpan(newEnds)
            syncRestDisplay(at: Date(), animated: false)
            coordinator.tickRestHaptics(at: Date())
        }
    }

    private var isRestingNow: Bool {
        coordinator.companionRestEndsAt.map { $0 > Date() } ?? false
    }

    private var tracksRestClock: Bool {
        coordinator.companionRestEndsAt != nil
    }

    @ViewBuilder
    private var restClock: some View {
        if tracksRestClock {
            TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 1)) { context in
                Color.clear
                    .onChange(of: remainingSeconds(at: context.date)) { _, newValue in
                        syncRestDisplay(seconds: newValue, animated: true)
                        coordinator.tickRestHaptics(at: context.date)
                    }
                    .onAppear {
                        syncRestDisplay(seconds: remainingSeconds(at: context.date), animated: false)
                        coordinator.tickRestHaptics(at: context.date)
                    }
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private func remainingSeconds(at date: Date) -> Int {
        guard let ends = coordinator.companionRestEndsAt else { return 0 }
        return max(0, Int(ends.timeIntervalSince(date).rounded(.down)))
    }

    private func syncRestDisplay(at date: Date, animated: Bool) {
        syncRestDisplay(seconds: remainingSeconds(at: date), animated: animated)
    }

    private func syncRestDisplay(seconds: Int, animated: Bool) {
        guard restDisplaySeconds != seconds else { return }
        if animated, !reduceMotion {
            withAnimation(WatchMotion.quickAnimation) {
                restDisplaySeconds = seconds
            }
        } else {
            restDisplaySeconds = seconds
        }
    }

    private func captureRestSpan(_ ends: Date?) {
        guard let ends, ends > Date() else {
            restWindowEnd = nil
            return
        }
        let key = floor(ends.timeIntervalSince1970)
        if let previous = restWindowEnd, previous != key {
            restSpanSeconds = max(1, restSpanSeconds + (key - previous))
            restWindowEnd = key
            return
        }
        if restWindowEnd == key { return }
        restWindowEnd = key
        restSpanSeconds = max(1, ends.timeIntervalSince(Date()))
    }

    private var headerRow: some View {
        HStack(spacing: WatchSpacing.xxs) {
            Circle()
                .fill(coordinator.isReachable ? WatchPalette.accent : WatchPalette.compromised)
                .frame(width: WatchLayout.liveDot, height: WatchLayout.liveDot)
            Text(coordinator.isReachable ? "Live" : "Reconnect")
                .watchType(.monoTag, color: WatchPalette.fgMuted)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var elapsedReadout: some View {
        if store.phase == .active || store.phase == .paused {
            WatchRollingTime(
                seconds: store.elapsedSeconds,
                style: .number,
                color: WatchPalette.fgMuted
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var exerciseBlock: some View {
        if let name = coordinator.companionExerciseName {
            Text(name)
                .watchType(.title)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }

        let tokens = WatchCompanionSetLine.tokens(
            setNumber: coordinator.companionSetNumber,
            setCount: coordinator.companionSetCount,
            targetSummary: coordinator.companionTargetSummary
        )
        if !tokens.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    Text(token.text)
                        .watchType(
                            token.isValue ? .number : .body,
                            color: token.isValue ? WatchPalette.fg : WatchPalette.fgSecondary
                        )
                        .fontWeight(token.isValue ? .bold : .regular)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(tokens.map(\.text).joined())
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch store.phase {
        case .active, .paused:
            if isRestingNow {
                restHero
            } else {
                heartRateHero
            }
        case .preparing:
            WatchLoadingState(message: "Starting HR")
        case .ending:
            WatchLoadingState(message: "Ending")
        case .idle, .ended:
            idleOrFailedBody
        }
    }

    private var restHero: some View {
        let remaining = Double(restDisplaySeconds)
        let progress = min(100, max(0, remaining / restSpanSeconds * 100))
        let urgent = restDisplaySeconds <= 5
        let state: WatchState = urgent ? .depleted : .ready
        return WatchArcGauge(value: progress, state: state) {
            VStack(spacing: 1) {
                WatchRollingTime(
                    seconds: restDisplaySeconds,
                    style: .heroNumber,
                    color: urgent ? WatchPalette.depleted : WatchPalette.accent
                )
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                if !isLuminanceReduced {
                    Text("Rest")
                        .watchType(.monoTag, color: WatchPalette.fgMuted)
                }
            }
        }
        .frame(height: isLuminanceReduced ? WatchLayout.heroArcAOD : WatchLayout.heroArc)
        .animation(
            WatchMotion.animation(WatchMotion.standardAnimation, reduceMotion: reduceMotion),
            value: urgent
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest \(restDisplaySeconds) seconds")
    }

    private var restChips: some View {
        HStack(spacing: WatchSpacing.xxs) {
            Button("−15") {
                coordinator.requestRestAdjust(deltaSeconds: -15)
            }
            .buttonStyle(.bordered)
            .tint(WatchPalette.fgSecondary)
            .accessibilityLabel("Subtract 15 seconds")

            Button("Skip") {
                coordinator.requestRestSkip()
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchPalette.accent)
            .foregroundStyle(WatchPalette.buttonPrimaryForeground)
            .accessibilityLabel("Skip rest")

            Button("+15") {
                coordinator.requestRestAdjust(deltaSeconds: 15)
            }
            .buttonStyle(.bordered)
            .tint(WatchPalette.fgSecondary)
            .accessibilityLabel("Add 15 seconds")
        }
        .font(WatchType.monoTag.font)
        .controlSize(.mini)
    }

    private var heartRateHero: some View {
        let zone = store.heartRateZone
        let state = zone.map(WatchState.heartRateZone) ?? .ready
        let bpm = store.heartRateBPM.map { Int($0.rounded()) }
        return WatchArcGauge(
            value: WatchZoneColor.progress(for: zone),
            state: state
        ) {
            VStack(spacing: 1) {
                if let bpm {
                    Text("\(bpm)")
                        .watchType(.heroNumber, color: WatchZoneColor.color(for: zone))
                        .watchNumericRoll(value: bpm, reduceMotion: reduceMotion)
                } else {
                    Text("--")
                        .watchType(.heroNumber, color: WatchPalette.fgSecondary)
                }
                if !isLuminanceReduced {
                    WatchZoneCaption(zone: zone)
                }
            }
            .animation(
                WatchMotion.animation(WatchMotion.quickAnimation, reduceMotion: reduceMotion),
                value: bpm
            )
        }
        .frame(height: isLuminanceReduced ? WatchLayout.heroArcAOD : WatchLayout.heroArc)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hrAccessibilityLabel(bpm: bpm, zone: zone))
    }

    private func hrAccessibilityLabel(bpm: Int?, zone: HeartRateZone?) -> String {
        let rate = bpm.map { "\($0) BPM" } ?? "No heart rate"
        if let zone {
            return "\(rate), \(zone.displayName)"
        }
        return rate
    }

    @ViewBuilder
    private var doneButton: some View {
        let setID = coordinator.companionSetID
        let isPending = setID.map { coordinator.pendingCompleteSetIDs.contains($0) } ?? false
        let canComplete = coordinator.companionSessionExerciseID != nil
            && setID != nil
            && (store.phase == .active || store.phase == .paused)
            && !isPending

        if canComplete || isPending {
            Button {
                guard
                    let exerciseID = coordinator.companionSessionExerciseID,
                    let setID
                else { return }
                coordinator.requestCompleteSet(sessionExerciseID: exerciseID, setID: setID)
                WatchHaptic.setLogged.play()
            } label: {
                Text(isPending ? "Sending" : "Done")
                    .font(WatchType.label.font)
                    .frame(maxWidth: .infinity, minHeight: WatchLayout.hit)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(WatchPalette.accent)
            .foregroundStyle(WatchPalette.buttonPrimaryForeground)
            .disabled(!canComplete)
            .accessibilityLabel(isPending ? "Sending set" : "Complete set")
        }
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let setID = coordinator.companionSetID,
           coordinator.pendingCompleteSetIDs.contains(setID) {
            Text(coordinator.isReachable ? "Sending" : "Queued")
                .watchType(.monoTag, color: WatchPalette.fgMuted)
        } else if !coordinator.isReachable {
            Text("Queues offline")
                .watchType(.monoTag, color: WatchPalette.fgSecondary)
        }
    }

    @ViewBuilder
    private var idleOrFailedBody: some View {
        if !store.isHealthKitAuthorized {
            WatchErrorState(
                title: "HealthKit required",
                message: "Allow heart rate on this Watch.",
                retryTitle: nil
            )
        } else if let error = store.lastError {
            WatchErrorState(message: error) {
                onRetryStart?()
            }
        } else if store.phase == .ended {
            WatchEmptyState(
                title: "Ended",
                message: "Keep the phone workout open."
            )
        } else {
            WatchLoadingState(message: "Starting HR")
        }
    }
}
