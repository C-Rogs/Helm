import SwiftUI

public enum HelmSkin: String, Sendable, CaseIterable, Identifiable {
    case instrument
    case dataSheet
    case stateField
    case blueprint

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .instrument: "Instrument"
        case .dataSheet: "Data sheet"
        case .stateField: "State field"
        case .blueprint: "Blueprint"
        }
    }

    /// Layout skins exposed in Settings. Additional cases stay reserved behind the seam.
    public static let selectableSkins: [HelmSkin] = [.instrument, .dataSheet]

    public var isSelectable: Bool {
        Self.selectableSkins.contains(self)
    }

    /// Vertical gap between major screen sections (Dashboard, Train, Trends).
    public var sectionSpacing: CGFloat {
        switch self {
        case .instrument: HelmSpacing.lg
        case .dataSheet: HelmSpacing.sm
        case .stateField, .blueprint: HelmSpacing.lg
        }
    }

    /// Instrument-only accent stripe on hero cards.
    public var usesAccentStripe: Bool {
        self == .instrument
    }

    /// Horizontal inset for ruled data-sheet sections.
    public var sectionHorizontalInset: CGFloat {
        switch self {
        case .dataSheet: 0
        case .instrument, .stateField, .blueprint: 0
        }
    }
}

private struct HelmSkinKey: EnvironmentKey {
    static let defaultValue: HelmSkin = .instrument
}

public extension EnvironmentValues {
    var helmSkin: HelmSkin {
        get { self[HelmSkinKey.self] }
        set { self[HelmSkinKey.self] = newValue }
    }
}

public struct SkinnedContainer<Content: View>: View {
    @Environment(\.helmSkin) private var skin
    @Environment(\.helmPalette) private var palette
    @Environment(\.helmSurfacePressed) private var isPressed

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        switch skin {
        case .instrument:
            instrumentBody
        case .dataSheet:
            dataSheetBody
        case .stateField:
            stateFieldBody
        case .blueprint:
            blueprintBody
        }
    }

    private var instrumentBody: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HelmSpacing.md)
            .background(
                isPressed ? palette.surfaceElevated : palette.surface,
                in: RoundedRectangle(cornerRadius: HelmRadius.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.card)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
    }

    private var dataSheetBody: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, HelmSpacing.md)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
            }
    }

    private var stateFieldBody: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HelmSpacing.md)
            .background(palette.accentFill ?? palette.accent)
    }

    private var blueprintBody: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HelmSpacing.md)
            .background(palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.sm)
                    .strokeBorder(palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
    }
}

public struct SkinnedGauge<Center: View>: View {
    @Environment(\.helmSkin) private var skin

    private let gauge: ArcGauge<Center>

    public init(_ gauge: ArcGauge<Center>) {
        self.gauge = gauge
    }

    public var body: some View {
        switch skin {
        case .instrument, .stateField:
            gauge
        case .dataSheet:
            gauge
                .padding(.vertical, HelmSpacing.xs)
        case .blueprint:
            gauge
        }
    }
}

public struct HelmScreenStack<Content: View>: View {
    @Environment(\.helmSkin) private var skin

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: skin.sectionSpacing) {
            content
        }
    }
}

private struct SkinAccentStripeModifier: ViewModifier {
    @Environment(\.helmSkin) private var skin

    let color: Color

    func body(content: Content) -> some View {
        if skin.usesAccentStripe {
            content.overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: HelmRadius.card)
                    .fill(color)
                    .frame(height: 3)
                    .padding(.horizontal, 1)
            }
        } else {
            content
        }
    }
}

public extension View {
    /// Instrument skin only: 3pt accent stripe along the top edge of a card.
    func skinAccentStripe(_ color: Color) -> some View {
        modifier(SkinAccentStripeModifier(color: color))
    }

    /// Standard horizontal screen gutter from the spacing scale.
    func helmScreenPadding() -> some View {
        padding(.horizontal, HelmSpacing.screenGutter)
    }
}
