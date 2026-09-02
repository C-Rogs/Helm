import SwiftUI

public struct LandmarkVolumeBar: View {
    private let label: String
    private let weeklySets: Double
    private let scheduledSets: Double
    private let mev: Int
    private let mrv: Int
    private let state: HelmState
    private let daysSinceTrained: Int?
    private let showsRecency: Bool

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var appearProgress: CGFloat = 0

    public init(
        label: String,
        weeklySets: Double,
        scheduledSets: Double = 0,
        mev: Int,
        mrv: Int,
        state: HelmState,
        daysSinceTrained: Int? = nil,
        showsRecency: Bool = false
    ) {
        self.label = label
        self.weeklySets = weeklySets
        self.scheduledSets = scheduledSets
        self.mev = mev
        self.mrv = mrv
        self.state = state
        self.daysSinceTrained = daysSinceTrained
        self.showsRecency = showsRecency
    }

    private var safeWeekly: Double { max(0, weeklySets) }
    private var safeScheduled: Double { max(0, scheduledSets) }
    private var safeMEV: Double { max(0, Double(mev)) }
    private var safeMRV: Double { max(1, Double(mrv)) }

    private var projectedSets: Double { safeWeekly + safeScheduled }

    private var scaleMax: Double {
        max(safeMRV * 1.15, projectedSets, safeMRV, 1)
    }

    /// One hue for both pills, from where the week lands. Avoids a colour break at MEV.
    private var fillState: HelmState {
        if safeScheduled > 0.05 {
            return HelmState.volumeWeekly(sets: projectedSets, mev: mev, mrv: mrv)
        }
        return state
    }

    private var fillColor: Color { HelmColor.color(for: fillState) }

    private var volumeStatus: VolumeLandmarkStatus {
        VolumeLandmarkStatus.resolve(sets: safeWeekly, mev: mev, mrv: mrv)
    }

    private var loggedReadout: String {
        "\(Int(safeWeekly.rounded()))"
    }

    private var drawProgress: CGFloat {
        reduceMotion ? 1 : appearProgress
    }

    private var stackHeight: CGFloat {
        HelmLayout.landmarkVolumeTrackHeight + HelmSpacing.xxs + HelmLayout.landmarkVolumeScaleHeight
    }

    public var body: some View {
        HStack(alignment: .top, spacing: HelmSpacing.sm) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(label)
                    .helmType(.label)
                    .lineLimit(1)
                if showsRecency {
                    Text(MuscleVolumeRecency.shortLabel(daysSinceTrained: daysSinceTrained))
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
            .frame(width: HelmSpacing.xl * 2.8, alignment: .leading)

            GeometryReader { geometry in
                let width = max(0, geometry.size.width)
                let mevX = width * CGFloat(safeMEV / scaleMax)
                let mrvX = width * CGFloat(safeMRV / scaleMax)
                let loggedWidth = width * CGFloat(safeWeekly / scaleMax) * drawProgress
                let projectedWidth = width * CGFloat(projectedSets / scaleMax) * drawProgress

                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    barStack(
                        width: width,
                        mevX: mevX,
                        mrvX: mrvX,
                        loggedWidth: loggedWidth,
                        projectedWidth: projectedWidth
                    )
                    scaleStack(width: width, mevX: mevX, mrvX: mrvX)
                }
            }
            .frame(height: stackHeight)
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: safeWeekly
            )
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: safeScheduled
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCopy)
        .onAppear(perform: beginAppearDraw)
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                appearProgress = 1
            }
        }
    }

    private func barStack(
        width: CGFloat,
        mevX: CGFloat,
        mrvX: CGFloat,
        loggedWidth: CGFloat,
        projectedWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(HelmColor.gaugeTrack)

                if projectedWidth > 0.5, safeScheduled > 0.05 {
                    Rectangle()
                        .fill(fillColor.opacity(0.45))
                        .frame(width: min(max(0, projectedWidth), width), height: HelmLayout.landmarkVolumeTrackHeight)
                }

                if loggedWidth > 0.5 {
                    Rectangle()
                        .fill(fillColor)
                        .frame(width: min(loggedWidth, width), height: HelmLayout.landmarkVolumeTrackHeight)
                }
            }
            .frame(width: width, height: HelmLayout.landmarkVolumeTrackHeight)
            .clipShape(Capsule())

            tick(at: mevX)
            tick(at: mrvX)

            if loggedWidth > 0.5 {
                loggedCountLabel(loggedWidth: min(loggedWidth, width), width: width)
            }
        }
        .frame(width: width, height: HelmLayout.landmarkVolumeTrackHeight)
    }

    private func scaleStack(width: CGFloat, mevX: CGFloat, mrvX: CGFloat) -> some View {
        let marks = visibleScaleMarks(
            zero: ScaleMark(id: "zero", text: "0", x: 0),
            mev: ScaleMark(id: "mev", text: "\(mev)", x: mevX),
            mrv: ScaleMark(id: "mrv", text: "\(mrv)", x: mrvX)
        )

        return ZStack(alignment: .topLeading) {
            ForEach(marks) { mark in
                VStack(spacing: HelmSpacing.xxs / 2) {
                    Rectangle()
                        .fill(HelmColor.fgSecondary.opacity(0.85))
                        .frame(width: 1, height: HelmSpacing.xxs)
                    Text(mark.text)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                        .lineLimit(1)
                }
                .position(
                    x: clampedCenterX(for: mark, width: width),
                    y: HelmLayout.landmarkVolumeScaleHeight / 2
                )
            }
        }
        .frame(width: width, height: HelmLayout.landmarkVolumeScaleHeight)
    }

    @ViewBuilder
    private func loggedCountLabel(loggedWidth: CGFloat, width: CGFloat) -> some View {
        let mark = ScaleMark(id: "logged", text: loggedReadout, x: loggedWidth / 2)
        let fitsInside = loggedWidth >= mark.estimatedWidth + HelmSpacing.xxs
        let x = fitsInside
            ? loggedWidth / 2
            : min(loggedWidth + HelmSpacing.xxs + mark.estimatedWidth / 2, width - HelmSpacing.xxs)
        Text(loggedReadout)
            .helmType(.monoTag, color: fitsInside ? HelmColor.canvas : fillColor)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .helmNumericRoll(value: loggedReadout)
            .position(x: x, y: HelmLayout.landmarkVolumeTrackHeight / 2)
    }

    private func tick(at x: CGFloat) -> some View {
        Rectangle()
            .fill(HelmColor.fgSecondary.opacity(0.85))
            .frame(width: 1, height: HelmLayout.landmarkVolumeTrackHeight - HelmSpacing.xxs)
            .offset(x: x - 0.5)
    }

    private func beginAppearDraw() {
        if reduceMotion {
            appearProgress = 1
            return
        }
        appearProgress = 0
        withAnimation(HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: false)) {
            appearProgress = 1
        }
    }

    private func visibleScaleMarks(zero: ScaleMark, mev: ScaleMark, mrv: ScaleMark) -> [ScaleMark] {
        var kept: [ScaleMark] = []
        for mark in [mev, mrv, zero] {
            let overlaps = kept.contains { existing in
                abs(existing.x - mark.x) < (existing.estimatedWidth + mark.estimatedWidth) / 2 + HelmSpacing.xxs
            }
            if !overlaps {
                kept.append(mark)
            }
        }
        return kept
    }

    private func clampedCenterX(for mark: ScaleMark, width: CGFloat) -> CGFloat {
        let half = mark.estimatedWidth / 2
        let pad = HelmSpacing.xxs
        return min(max(mark.x, pad + half), max(pad + half, width - pad - half))
    }

    private var accessibilityCopy: String {
        if safeScheduled > 0.05 {
            return "\(label), \(Int(safeWeekly.rounded())) logged, \(Int(safeScheduled.rounded())) scheduled, landmark \(mev) to \(mrv), \(volumeStatus.label)"
        }
        return "\(label), \(Int(safeWeekly.rounded())) sets of \(mev) to \(mrv), \(volumeStatus.label)"
    }
}

private struct ScaleMark: Identifiable {
    let id: String
    let text: String
    let x: CGFloat

    var estimatedWidth: CGFloat {
        CGFloat(max(text.count, 1)) * HelmSpacing.sm
    }
}

#if DEBUG
#Preview("Landmark volume bars") {
    VStack(spacing: HelmSpacing.md) {
        LandmarkVolumeBar(
            label: "Chest",
            weeklySets: 0,
            scheduledSets: 8,
            mev: 9,
            mrv: 22,
            state: .depleted,
            daysSinceTrained: 4,
            showsRecency: true
        )
        LandmarkVolumeBar(
            label: "Shoulders",
            weeklySets: 3,
            scheduledSets: 5,
            mev: 8,
            mrv: 20,
            state: .depleted,
            daysSinceTrained: 1,
            showsRecency: true
        )
        LandmarkVolumeBar(
            label: "Triceps",
            weeklySets: 0,
            scheduledSets: 6,
            mev: 6,
            mrv: 16,
            state: .depleted,
            daysSinceTrained: 3,
            showsRecency: true
        )
        LandmarkVolumeBar(
            label: "Back",
            weeklySets: 2,
            mev: 9,
            mrv: 22,
            state: .depleted,
            daysSinceTrained: 2,
            showsRecency: true
        )
        LandmarkVolumeBar(
            label: "Hams",
            weeklySets: 22,
            mev: 8,
            mrv: 16,
            state: .compromised,
            daysSinceTrained: 1,
            showsRecency: true
        )
    }
    .padding()
    .helmTheme()
}

#Preview("Landmark volume reduce motion") {
    LandmarkVolumeBar(label: "Quads", weeklySets: 10, scheduledSets: 4, mev: 8, mrv: 18, state: .ready)
        .padding()
        .helmTheme()
        .environment(\.helmReduceMotion, true)
}
#endif
