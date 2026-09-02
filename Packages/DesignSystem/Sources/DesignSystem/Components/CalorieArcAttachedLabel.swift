import SwiftUI

struct CalorieArcAttachedLabelView: View {
    let item: CalorieArcModel.AttachedLabel
    let fillState: HelmState
    let isOver: Bool

    var body: some View {
        let dock = CalorieArcLabelDock.resolve(anchor: item.anchor, fraction: item.fraction)
        VStack(alignment: dock.stackAlignment, spacing: 0) {
            if let caption = item.caption {
                Text(caption)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            valueText
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .multilineTextAlignment(dock.textAlignment)
        .padding(dock.padding)
        .frame(
            maxWidth: HelmSpacing.lg * 2,
            alignment: dock.frameAlignment
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var valueText: some View {
        let style: HelmType = item.anchor == .radial ? .monoTag : .number
        if item.value.allSatisfy(\.isNumber) || item.value.contains("k") {
            HelmNumericText(item.value)
                .helmType(style, color: valueColor)
        } else {
            Text(item.value)
                .helmType(style, color: valueColor)
        }
    }

    private var valueColor: Color {
        switch item.role {
        case .target:
            HelmColor.fg
        case .progress:
            isOver ? HelmColor.depleted : HelmColor.color(for: fillState)
        case .origin, .scaleEnd:
            HelmColor.fgMuted
        }
    }
}

struct CalorieArcLabelAnchor: View {
    let item: CalorieArcModel.AttachedLabel
    let drawable: CGFloat
    let stroke: CGFloat
    let fillState: HelmState
    let isOver: Bool

    var body: some View {
        let dock = CalorieArcLabelDock.resolve(anchor: item.anchor, fraction: item.fraction)
        let center = CGPoint(x: drawable / 2, y: drawable / 2)
        let footRadius = (drawable - stroke) / 2 + stroke / 2 + 2
        let foot = HelmArcGeometry.point(fraction: item.fraction, center: center, radius: footRadius)

        Color.clear
            .frame(width: 1, height: 1)
            .overlay(alignment: dock.overlayAlignment) {
                CalorieArcAttachedLabelView(item: item, fillState: fillState, isOver: isOver)
            }
            .position(x: foot.x, y: foot.y)
    }
}

enum CalorieArcLabelDock: Equatable {
    case gapStart
    case gapEnd
    case left
    case topLeft
    case top
    case topRight
    case right

    var overlayAlignment: Alignment {
        switch self {
        case .gapStart: .topLeading
        case .gapEnd: .topTrailing
        case .left: .trailing
        case .topLeft: .bottomTrailing
        case .top: .bottom
        case .topRight: .bottomLeading
        case .right: .leading
        }
    }

    var stackAlignment: HorizontalAlignment {
        switch self {
        case .gapEnd, .left, .topLeft: .trailing
        case .top: .center
        case .gapStart, .right, .topRight: .leading
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .gapEnd, .left, .topLeft: .trailing
        case .top: .center
        case .gapStart, .right, .topRight: .leading
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .gapEnd, .left, .topLeft: .trailing
        case .top: .center
        case .gapStart, .right, .topRight: .leading
        }
    }

    var padding: EdgeInsets {
        switch self {
        case .gapStart:
            EdgeInsets(top: HelmSpacing.xxs, leading: HelmSpacing.xxs, bottom: 0, trailing: 0)
        case .gapEnd:
            EdgeInsets(top: HelmSpacing.xxs, leading: 0, bottom: 0, trailing: HelmSpacing.xxs)
        case .left:
            EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: HelmSpacing.xxs)
        case .right:
            EdgeInsets(top: 0, leading: HelmSpacing.xxs, bottom: 0, trailing: 0)
        case .top:
            EdgeInsets(top: 0, leading: HelmSpacing.xxs, bottom: HelmSpacing.xxs, trailing: HelmSpacing.xxs)
        case .topLeft:
            EdgeInsets(top: 0, leading: 0, bottom: HelmSpacing.xxs, trailing: HelmSpacing.xxs)
        case .topRight:
            EdgeInsets(top: 0, leading: HelmSpacing.xxs, bottom: HelmSpacing.xxs, trailing: 0)
        }
    }

    static func resolve(
        anchor: CalorieArcModel.LabelAnchor,
        fraction: Double
    ) -> CalorieArcLabelDock {
        switch anchor {
        case .gapStart: .gapStart
        case .gapEnd: .gapEnd
        case .radial:
            switch fraction {
            case ..<0.22: .left
            case ..<0.38: .topLeft
            case ..<0.62: .top
            case ..<0.78: .topRight
            default: .right
            }
        }
    }
}
