import SwiftUI

/// Energy-balance instrument: 270-degree arc with dynamic allowance bands, eat-to tick, and intake fill.
public struct CalorieArcGauge: View {
    private let model: CalorieArcModel

    @Environment(\.helmReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drawProgress: Double = 0

    public init(model: CalorieArcModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: HelmSpacing.md) {
            gauge
                .frame(maxWidth: HelmLayout.calorieArcMaxWidth)
                .frame(maxWidth: .infinity)
                .arcStateBloom(
                    progress: model.loggedFraction,
                    state: model.fillState,
                    reduceMotion: reduceMotion
                )

            legend
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .animation(
            HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
            value: model.loggedFraction
        )
        .animation(
            HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
            value: model.eatToFraction
        )
        .onAppear(perform: beginDraw)
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced { drawProgress = 1 }
        }
    }

    private var gauge: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let stroke = HelmArcGeometry.calorieStrokeWidth(radius: side / 2)
            let labelPad = HelmSpacing.lg
            let drawable = max(side - labelPad * 2, 1)
            let origin = CGPoint(
                x: (geometry.size.width - drawable) / 2,
                y: (geometry.size.height - drawable) / 2
            )

            ZStack {
                arcStack(drawable: drawable, stroke: stroke)

                tickCanvas(drawable: drawable, stroke: stroke)
                    .frame(width: drawable, height: drawable)

                attachedLabels(drawable: drawable, stroke: stroke)

                centerReadout
                    .offset(y: -HelmSpacing.sm)
                    .padding(.horizontal, HelmSpacing.md)

                if model.showsHoleEatTo(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                    VStack {
                        Spacer(minLength: 0)
                        holeEatTo
                    }
                    .padding(.bottom, HelmSpacing.sm)
                    .frame(width: drawable, height: drawable)
                }
            }
            .frame(width: drawable, height: drawable)
            .position(
                x: origin.x + drawable / 2,
                y: origin.y + drawable / 2
            )
        }
        .clipped()
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func arcStack(drawable: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            arcSegment(from: 0, to: 1, color: HelmColor.gaugeTrack, stroke: stroke, side: drawable)

            ForEach(model.bands) { band in
                arcSegment(
                    from: band.start,
                    to: band.end,
                    color: bandColor(band.kind),
                    stroke: stroke,
                    side: drawable
                )
            }

            ForEach(model.fills(drawProgress: drawProgress)) { fill in
                arcSegment(
                    from: fill.start,
                    to: fill.end,
                    color: fillColor(fill.kind),
                    stroke: stroke,
                    side: drawable
                )
            }
        }
        .frame(width: drawable, height: drawable)
    }

    @ViewBuilder
    private func arcSegment(
        from start: Double,
        to end: Double,
        color: Color,
        stroke: CGFloat,
        side: CGFloat
    ) -> some View {
        let lo = min(max(start, 0), 1)
        let hi = min(max(end, 0), 1)
        if hi > lo + CalorieArcMetrics.visibleFillEpsilon {
            Circle()
                .trim(
                    from: CGFloat(lo * HelmArcGeometry.sweepFraction),
                    to: CGFloat(hi * HelmArcGeometry.sweepFraction)
                )
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                .rotationEffect(.degrees(HelmArcGeometry.rotationDegrees))
                .frame(width: side - stroke, height: side - stroke)
        }
    }

    private func tickCanvas(drawable: CGFloat, stroke: CGFloat) -> some View {
        let radius = (drawable - stroke) / 2
        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for tick in model.ticks {
                let innerExtra: CGFloat
                let outerExtra: CGFloat
                let width: CGFloat
                let color: Color
                switch tick.kind {
                case .target:
                    innerExtra = 4
                    outerExtra = 7
                    width = 2
                    color = HelmColor.fg
                case .progress:
                    innerExtra = 2
                    outerExtra = 4
                    width = 1.5
                    color = model.isOver ? HelmColor.depleted : HelmColor.color(for: model.fillState)
                case .scaleEnd:
                    innerExtra = 3
                    outerExtra = 5
                    width = 1.5
                    color = HelmColor.fgSecondary.opacity(0.9)
                case .minor:
                    innerExtra = 1
                    outerExtra = 2
                    width = 1
                    color = HelmColor.fgMuted.opacity(0.4)
                }
                let inner = HelmArcGeometry.point(
                    fraction: tick.fraction,
                    center: center,
                    radius: radius - stroke / 2 - innerExtra
                )
                let outer = HelmArcGeometry.point(
                    fraction: tick.fraction,
                    center: center,
                    radius: radius + stroke / 2 + outerExtra
                )
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                context.stroke(path, with: .color(color), lineWidth: width)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func attachedLabels(drawable: CGFloat, stroke: CGFloat) -> some View {
        let labels = model.visibleAttachedLabels(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
        return ZStack {
            ForEach(labels) { item in
                CalorieArcLabelAnchor(
                    item: item,
                    drawable: drawable,
                    stroke: stroke,
                    fillState: model.fillState,
                    isOver: model.isOver
                )
            }
        }
        .frame(width: drawable, height: drawable)
        .allowsHitTesting(false)
    }

    private var holeEatTo: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
                Text("EAT-TO")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                HelmNumericText(model.eatToKcal)
                    .helmType(.number, color: HelmColor.fg)
            }
            .lineLimit(1)

            VStack(spacing: 0) {
                Text("EAT-TO")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                HelmNumericText(model.eatToKcal)
                    .helmType(.number, color: HelmColor.fg)
            }
        }
        .minimumScaleFactor(0.75)
    }

    private var centerReadout: some View {
        VStack(spacing: HelmSpacing.xxs) {
            ViewThatFits {
                HelmNumericText(model.centerValue)
                    .helmType(.heroNumber, color: centerColor)
                HelmNumericText(model.centerValue)
                    .helmType(.bigNumber, color: centerColor)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(model.centerCaption)
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var legend: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                ForEach(model.legend) { item in
                    CalorieArcLegendChip(item: item, fillState: model.fillState)
                }
            }
        } else {
            HStack(alignment: .top, spacing: HelmSpacing.sm) {
                ForEach(model.legend) { item in
                    CalorieArcLegendChip(item: item, fillState: model.fillState)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var centerColor: Color {
        if model.isOver { return HelmColor.depleted }
        if model.hasLogged, model.loggedKcal > 0 {
            return HelmColor.color(for: model.fillState)
        }
        return HelmColor.fg
    }

    private func bandColor(_ kind: CalorieArcModel.BandKind) -> Color {
        switch kind {
        case .baseline: HelmColor.ready.opacity(0.22)
        case .active: HelmColor.accent.opacity(0.28)
        }
    }

    private func fillColor(_ kind: CalorieArcModel.FillKind) -> Color {
        switch kind {
        case .intake:
            if model.isOver { return HelmColor.color(for: .primed) }
            return HelmColor.color(for: model.fillState)
        case .over:
            return HelmColor.depleted
        }
    }

    private func beginDraw() {
        if reduceMotion {
            drawProgress = 1
            return
        }
        drawProgress = 0
        withAnimation(HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: false)) {
            drawProgress = 1
        }
    }
}

private struct CalorieArcLegendChip: View {
    let item: CalorieArcModel.LegendItem
    let fillState: HelmState

    var body: some View {
        HStack(alignment: .center, spacing: HelmSpacing.xs) {
            Circle()
                .fill(swatchColor)
                .frame(width: HelmSpacing.xs - 2, height: HelmSpacing.xs - 2)

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(item.label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                valueReadout
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var valueReadout: some View {
        if item.value.allSatisfy(\.isNumber) {
            HelmNumericText(item.value)
                .helmType(.number, color: valueColor)
        } else {
            Text(item.value)
                .helmType(.number, color: valueColor)
        }
    }

    private var valueColor: Color {
        if let state = item.state {
            return HelmColor.color(for: state)
        }
        return HelmColor.fg
    }

    private var swatchColor: Color {
        switch item.swatch {
        case .baseline: HelmColor.ready.opacity(0.9)
        case .active: HelmColor.accent
        case .intake: HelmColor.color(for: fillState)
        case .over: HelmColor.depleted
        case .muted: HelmColor.fgMuted
        }
    }
}

#if DEBUG
#Preview("Calorie arc under with active") {
    CalorieArcGauge(
        model: CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_800, active: .fresh(420))
    )
    .padding()
    .helmTheme()
}

#Preview("Calorie arc over into active") {
    CalorieArcGauge(
        model: CalorieArcModel(eatToKcal: 2_400, loggedKcal: 2_650, active: .fresh(420))
    )
    .padding()
    .helmTheme()
}

#Preview("Calorie arc over past active") {
    CalorieArcGauge(
        model: CalorieArcModel(eatToKcal: 2_400, loggedKcal: 3_100, active: .fresh(420))
    )
    .padding()
    .helmTheme()
}

#Preview("Calorie arc no active") {
    CalorieArcGauge(
        model: CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_100, active: .none)
    )
    .padding()
    .helmTheme()
}

#Preview("Calorie arc empty") {
    CalorieArcGauge(
        model: CalorieArcModel(eatToKcal: 2_200, loggedKcal: nil, active: .syncing)
    )
    .padding()
    .helmTheme()
}

#Preview("Calorie arc near eat-to") {
    CalorieArcGauge(
        model: CalorieArcModel(eatToKcal: 2_400, loggedKcal: 2_320, active: .none)
    )
    .padding()
    .helmTheme()
}

#Preview("Calorie arc light") {
    CalorieArcGauge(
        model: CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_800, active: .fresh(420))
    )
    .padding()
    .helmTheme()
    .environment(\.colorScheme, .light)
}

#Preview("Calorie arc accessibility") {
    CalorieArcGauge(
        model: CalorieArcModel(eatToKcal: 2_400, loggedKcal: 1_800, active: .fresh(420))
    )
    .padding()
    .helmTheme()
    .dynamicTypeSize(.accessibility3)
}
#endif
