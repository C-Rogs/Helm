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

    public var isAvailableInV1: Bool {
        self == .instrument
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

    private let isPressed: Bool
    private let content: Content

    public init(isPressed: Bool = false, @ViewBuilder content: () -> Content) {
        self.isPressed = isPressed
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
            .padding(.vertical, HelmSpacing.sm)
            .overlay(alignment: .bottom) {
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
        case .instrument, .dataSheet, .blueprint:
            gauge
        case .stateField:
            gauge
        }
    }
}
