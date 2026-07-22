import SwiftUI

public struct ArcGauge<Center: View>: View {
    private let value: Double
    private let range: ClosedRange<Double>
    private let state: HelmState
    private let trackColor: Color
    private let lineWidth: CGFloat?
    private let center: Center

    public init(
        value: Double,
        range: ClosedRange<Double> = 0 ... 100,
        state: HelmState,
        track: Color = HelmColor.hairline,
        lineWidth: CGFloat? = nil,
        @ViewBuilder center: () -> Center
    ) {
        self.value = value
        self.range = range
        self.state = state
        self.trackColor = track
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side / 2
            let stroke = resolvedLineWidth(radius: radius)

            ZStack {
                arcLayer(
                    progress: 1,
                    color: trackColor,
                    lineWidth: stroke,
                    side: side
                )

                arcLayer(
                    progress: normalizedValue,
                    color: HelmColor.color(for: state),
                    lineWidth: stroke,
                    side: side
                )

                center
            }
            .frame(width: side, height: side)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var normalizedValue: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func resolvedLineWidth(radius: CGFloat) -> CGFloat {
        if let lineWidth { return lineWidth }
        return min(radius * 0.12, 14)
    }

    private func arcLayer(
        progress: Double,
        color: Color,
        lineWidth: CGFloat,
        side: CGFloat
    ) -> some View {
        Circle()
            .trim(from: 0, to: progress * 0.75)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(135))
            .frame(width: side - lineWidth, height: side - lineWidth)
    }
}

public extension ArcGauge where Center == EmptyView {
    init(
        value: Double,
        range: ClosedRange<Double> = 0 ... 100,
        state: HelmState,
        track: Color = HelmColor.hairline,
        lineWidth: CGFloat? = nil
    ) {
        self.init(
            value: value,
            range: range,
            state: state,
            track: track,
            lineWidth: lineWidth
        ) {
            EmptyView()
        }
    }
}

#if DEBUG
#Preview("ArcGauge states") {
    ScrollView {
        VStack(spacing: HelmSpacing.lg) {
            ForEach(HelmState.allCases, id: \.self) { state in
                ArcGauge(
                    value: state == .depleted ? 28 : state == .compromised ? 48 : state == .ready ? 64 : 82,
                    state: state
                ) {
                    VStack(spacing: HelmSpacing.xxs) {
                        Text("64")
                            .helmType(.heroNumber)
                        Text(state.label)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }
                .frame(maxWidth: 220)
            }
        }
        .padding(HelmSpacing.screenGutter)
    }
    .helmTheme()
}
#endif
