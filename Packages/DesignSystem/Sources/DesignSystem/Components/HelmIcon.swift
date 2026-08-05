import SwiftUI

/// Documented SF Symbol catalog. One weight and size per context; see `Docs/ICONOGRAPHY.md`.
public enum HelmIcon: String, CaseIterable, Sendable {
    case dashboard = "gauge.with.dots.needle.67percent"
    case train = "dumbbell"
    case nutrition = "fork.knife"
    case chat = "bubble.left.and.bubble.right"
    case settings = "gearshape"
    case health = "heart.text.square"
    case trends = "chart.xyaxis.line"
    case chevronRight = "chevron.right"
    case chevronDown = "chevron.down"
    case chevronUp = "chevron.up"
    case info = "info.circle"
    case checkmark = "checkmark.circle"
    case checkmarkFilled = "checkmark.circle.fill"
    case circle = "circle"
    case scale = "scalemass"
    case trash = "trash"
    case plus = "plus.circle.fill"
    case send = "arrow.up.circle.fill"
    case mic = "mic.fill"
    case refresh = "arrow.clockwise"
    case photo = "photo.on.rectangle"
    case camera = "camera.fill"
    case search = "magnifyingglass"
    case barcode = "barcode.viewfinder"
    case offline = "wifi.slash"
    case swap = "arrow.triangle.swap"
    case arrowRight = "arrow.right"
    case empty = "tray"
    case error = "exclamationmark.triangle"
    case coach = "bubble.left.and.bubble.right.fill"
}

public enum HelmIconContext: Sendable {
    case tab
    case section
    case inline
    case action

    public var pointSize: CGFloat {
        switch self {
        case .tab: 22
        case .section: 20
        case .inline: 15
        case .action: 28
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .tab: .medium
        case .section: .regular
        case .inline: .regular
        case .action: .semibold
        }
    }
}

public struct HelmIconView: View {
    private let icon: HelmIcon
    private let context: HelmIconContext

    public init(_ icon: HelmIcon, context: HelmIconContext = .inline) {
        self.icon = icon
        self.context = context
    }

    public var body: some View {
        Image(systemName: icon.rawValue)
            .font(.system(size: context.pointSize, weight: context.weight))
            .imageScale(context == .tab ? .medium : .small)
    }
}

public extension Label where Title == Text, Icon == HelmIconView {
    @MainActor
    init(_ title: String, helmIcon: HelmIcon, context: HelmIconContext = .inline) {
        self.init {
            Text(title)
        } icon: {
            HelmIconView(helmIcon, context: context)
        }
    }
}

#Preview("Icon contexts") {
    VStack(alignment: .leading, spacing: HelmSpacing.md) {
        HStack(spacing: HelmSpacing.lg) {
            HelmIconView(.dashboard, context: .tab)
            HelmIconView(.train, context: .tab)
            HelmIconView(.nutrition, context: .tab)
            HelmIconView(.chat, context: .tab)
            HelmIconView(.settings, context: .tab)
        }
        HelmIconView(.trends, context: .section)
        HelmIconView(.info, context: .inline)
        HelmIconView(.send, context: .action)
    }
    .foregroundStyle(HelmColor.fg)
    .padding()
    .helmTheme()
}
