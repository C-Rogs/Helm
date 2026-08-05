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
            .frame(width: HelmSpacing.xl * 2.2, alignment: .leading)

            GeometryReader { geometry in
                let width = max(0, geometry.size.width)
                let mevX = width * CGFloat(safeMEV / scaleMax)
                let mrvX = width * CGFloat(safeMRV / scaleMax)
                let loggedWidth = width * CGFloat(safeWeekly / scaleMax)
                let projectedWidth = width * CGFloat(projectedSets / scaleMax)

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
                }
            }
            .frame(height: 6)

            VStack(alignment: .trailing, spacing: 0) {
                if safeScheduled > 0.05 {
                    let scheduledReadout = "\(Int(safeWeekly.rounded()))+\(Int(safeScheduled.rounded()))"
                    Text(scheduledReadout)
                        .helmType(.number, color: HelmColor.color(for: state))
                        .helmNumericRoll(value: scheduledReadout)
                } else {
                    HelmNumericText(safeWeekly, format: "%.0f")
                        .helmType(.number, color: HelmColor.color(for: state))
                }
                Text(state.label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
            .frame(width: HelmSpacing.xl + HelmSpacing.md, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCopy)
    }

    private var accessibilityCopy: String {
        if safeScheduled > 0.05 {
            return "\(label), \(Int(safeWeekly.rounded())) logged, \(Int(safeScheduled.rounded())) scheduled, \(state.label)"
        }
        return "\(label), \(Int(safeWeekly.rounded())) sets, \(state.label)"
    }
}

#if DEBUG
#Preview("Landmark volume bars") {
    VStack(spacing: HelmSpacing.md) {
        LandmarkVolumeBar(label: "Quads", weeklySets: 4, scheduledSets: 6, mev: 8, mrv: 18, state: .ready)
        LandmarkVolumeBar(label: "Chest", weeklySets: 12, mev: 10, mrv: 20, state: .ready)
        LandmarkVolumeBar(label: "Back", weeklySets: 18, scheduledSets: 4, mev: 10, mrv: 18, state: .compromised)
        LandmarkVolumeBar(label: "Hams", weeklySets: 22, mev: 8, mrv: 16, state: .compromised)
    }
    .padding()
    .helmTheme()
}
#endif
