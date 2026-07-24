import SwiftUI

public struct LandmarkVolumeBar: View {
    private let label: String
    private let weeklySets: Double
    private let mev: Int
    private let mrv: Int
    private let state: HelmState

    public init(
        label: String,
        weeklySets: Double,
        mev: Int,
        mrv: Int,
        state: HelmState
    ) {
        self.label = label
        self.weeklySets = weeklySets
        self.mev = mev
        self.mrv = mrv
        self.state = state
    }

    private var scaleMax: Double {
        max(Double(mrv) * 1.15, weeklySets, Double(mrv))
    }

    public var body: some View {
        HStack(spacing: HelmSpacing.sm) {
            Text(label)
                .helmType(.label)
                .lineLimit(1)
                .frame(width: HelmSpacing.xl * 2.2, alignment: .leading)

            GeometryReader { geometry in
                let width = geometry.size.width
                let mevX = width * CGFloat(Double(mev) / scaleMax)
                let mrvX = width * CGFloat(Double(mrv) / scaleMax)
                let fillWidth = width * CGFloat(weeklySets / scaleMax)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HelmColor.gaugeTrack)

                    Capsule()
                        .fill(HelmColor.ready.opacity(0.22))
                        .frame(width: max(mrvX - mevX, 0))
                        .offset(x: mevX)

                    Capsule()
                        .fill(HelmColor.color(for: state))
                        .frame(width: min(fillWidth, width))
                }
            }
            .frame(height: 6)

            VStack(alignment: .trailing, spacing: 0) {
                HelmNumericText(weeklySets, format: "%.0f")
                    .helmType(.number, color: HelmColor.color(for: state))
                Text(state.label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
            .frame(width: HelmSpacing.xl + HelmSpacing.sm, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(Int(weeklySets.rounded())) sets, \(state.label)")
    }
}

#if DEBUG
#Preview("Landmark volume bars") {
    VStack(spacing: HelmSpacing.md) {
        LandmarkVolumeBar(label: "Quads", weeklySets: 4, mev: 8, mrv: 18, state: .depleted)
        LandmarkVolumeBar(label: "Chest", weeklySets: 12, mev: 10, mrv: 20, state: .ready)
        LandmarkVolumeBar(label: "Back", weeklySets: 18, mev: 10, mrv: 18, state: .primed)
        LandmarkVolumeBar(label: "Hams", weeklySets: 22, mev: 8, mrv: 16, state: .compromised)
    }
    .padding()
    .helmTheme()
}
#endif
