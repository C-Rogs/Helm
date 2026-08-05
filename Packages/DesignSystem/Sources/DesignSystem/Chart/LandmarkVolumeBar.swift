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

    private var volumeStatus: VolumeLandmarkStatus {
        VolumeLandmarkStatus.resolve(sets: safeWeekly, mev: mev, mrv: mrv)
    }

    private var setsReadout: String {
        let logged = Int(safeWeekly.rounded())
        if safeScheduled > 0.05 {
            return "\(logged)+\(Int(safeScheduled.rounded())) / \(mev)-\(mrv)"
        }
        return "\(logged) / \(mev)-\(mrv)"
    }

    private var drawProgress: CGFloat {
        reduceMotion ? 1 : appearProgress
    }

    public var body: some View {
        HStack(spacing: HelmSpacing.sm) {
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

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HelmColor.gaugeTrack)

                    Capsule()
                        .fill(HelmColor.ready.opacity(0.22))
                        .frame(width: max(mrvX - mevX, 0))
                        .offset(x: mevX)

                    if safeScheduled > 0.05 {
                        Capsule()
                            .fill(HelmColor.color(for: state).opacity(0.35))
                            .frame(width: min(max(0, projectedWidth), width))
                    }

                    Capsule()
                        .fill(HelmColor.color(for: state))
                        .frame(width: min(max(0, loggedWidth), width))

                    tick(at: mevX, height: geometry.size.height)
                    tick(at: mrvX, height: geometry.size.height)
                }
            }
            .frame(height: 8)
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: safeWeekly
            )
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: safeScheduled
            )

            VStack(alignment: .trailing, spacing: 0) {
                Text(setsReadout)
                    .helmType(.number, color: HelmColor.color(for: state))
                    .helmNumericRoll(value: setsReadout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(volumeStatus.label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .lineLimit(1)
            }
            .frame(width: HelmSpacing.xl * 3.4, alignment: .trailing)
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

    private func tick(at x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(HelmColor.fgSecondary.opacity(0.85))
            .frame(width: 1, height: max(height + 4, 10))
            .offset(x: x - 0.5, y: -2)
    }

    private var accessibilityCopy: String {
        if safeScheduled > 0.05 {
            return "\(label), \(Int(safeWeekly.rounded())) logged, \(Int(safeScheduled.rounded())) scheduled, landmark \(mev) to \(mrv), \(volumeStatus.label)"
        }
        return "\(label), \(Int(safeWeekly.rounded())) sets of \(mev) to \(mrv), \(volumeStatus.label)"
    }
}

#if DEBUG
#Preview("Landmark volume bars") {
    VStack(spacing: HelmSpacing.md) {
        LandmarkVolumeBar(label: "Quads", weeklySets: 4, scheduledSets: 6, mev: 8, mrv: 18, state: .ready)
        LandmarkVolumeBar(label: "Chest", weeklySets: 12, mev: 10, mrv: 20, state: .ready)
        LandmarkVolumeBar(label: "Back", weeklySets: 18, scheduledSets: 4, mev: 10, mrv: 18, state: .compromised)
        LandmarkVolumeBar(label: "Hams", weeklySets: 22, mev: 8, mrv: 16, state: .compromised)
        LandmarkVolumeBar(label: "Abs", weeklySets: 6, mev: 4, mrv: 12, state: .ready)
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
