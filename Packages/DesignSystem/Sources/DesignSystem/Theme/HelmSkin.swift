import SwiftUI

public enum HelmSkin: String, Sendable, CaseIterable, Identifiable {
    case signal
    case instrument
    case dataSheet
    case stateField
    case blueprint

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .signal: "Signal"
        case .instrument: "Instrument"
        case .dataSheet: "Data sheet"
        case .stateField: "State field"
        case .blueprint: "Blueprint"
        }
    }

    /// Layout skins exposed in Settings. Additional cases stay reserved behind the seam.
    public static let selectableSkins: [HelmSkin] = [.signal, .instrument, .dataSheet]

    public var isSelectable: Bool {
        Self.selectableSkins.contains(self)
    }

    /// Vertical gap between major screen sections (Dashboard, Train, Trends).
    public var sectionSpacing: CGFloat {
        switch self {
        case .signal: HelmSpacing.md
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
        case .signal, .instrument, .stateField, .blueprint: 0
        }
    }

    /// Soft press scale for Signal; slightly firmer for card skins.
    public var pressScale: CGFloat {
        switch self {
        case .signal: 0.992
        case .instrument, .dataSheet, .stateField, .blueprint: 0.985
        }
    }

    /// Whether major screen stacks should stagger children on appear.
    public var usesStaggeredAppear: Bool {
        self == .signal
    }
}

private struct HelmSkinKey: EnvironmentKey {
    static let defaultValue: HelmSkin = .signal
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
        case .signal:
            signalBody
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

    private var signalBody: some View {
        content
            .signalHUDPanel(emphasized: isPressed)
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
        case .signal:
            gauge
                .padding(.vertical, HelmSpacing.sm)
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
    @Environment(\.helmReduceMotion) private var reduceMotion

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: skin.sectionSpacing) {
            content
        }
        .modifier(SignalStaggerModifier(enabled: skin.usesStaggeredAppear, reduceMotion: reduceMotion))
    }
}

private struct SignalStaggerModifier: ViewModifier {
    let enabled: Bool
    let reduceMotion: Bool
    @State private var appeared = false

    func body(content: Content) -> some View {
        // Opacity-only screen fade; per-child helmStaggeredAppear owns motion offset.
        content
            .opacity(shouldFade ? (appeared ? 1 : 0.01) : 1)
            .animation(
                HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                value: appeared
            )
            .onAppear {
                guard shouldFade else { return }
                appeared = true
            }
    }

    private var shouldFade: Bool {
        enabled && !reduceMotion
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
