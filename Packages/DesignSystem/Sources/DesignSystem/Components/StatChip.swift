import SwiftUI

public struct StatChip: View {
    @Environment(\.helmSkin) private var skin
    @Environment(\.helmPalette) private var palette

    private let label: String
    private let value: String
    private let state: HelmState?

    public init(label: String, value: String, state: HelmState? = nil) {
        self.label = label
        self.value = value
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(value)
                .helmType(.number, color: valueColor)
                .helmNumericRoll(value: value)
            Text(label)
                .helmType(.monoTag, color: palette.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(chipPadding)
        .background(chipBackground)
        .overlay(chipOverlay)
    }

    private var chipPadding: EdgeInsets {
        switch skin {
        case .signal:
            EdgeInsets(top: HelmSpacing.sm, leading: HelmSpacing.sm, bottom: HelmSpacing.sm, trailing: HelmSpacing.sm)
        case .dataSheet:
            EdgeInsets(top: HelmSpacing.sm, leading: 0, bottom: HelmSpacing.sm, trailing: 0)
        case .instrument, .stateField, .blueprint:
            EdgeInsets(top: HelmSpacing.sm, leading: HelmSpacing.sm, bottom: HelmSpacing.sm, trailing: HelmSpacing.sm)
        }
    }

    @ViewBuilder
    private var chipBackground: some View {
        switch skin {
        case .signal:
            Color.clear
        case .dataSheet:
            Color.clear
        case .instrument, .stateField, .blueprint:
            palette.surfaceElevated
                .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
    }

    @ViewBuilder
    private var chipOverlay: some View {
        switch skin {
        case .signal:
            SignalHUDFrame(emphasized: false)
        case .dataSheet:
            VStack {
                Spacer()
                Rectangle()
                    .fill(palette.hairline)
                    .frame(height: 1)
            }
        case .instrument, .stateField, .blueprint:
            EmptyView()
        }
    }

    private var valueColor: Color {
        if let state {
            return HelmColor.color(for: state)
        }
        return palette.fg
    }
}

#Preview("StatChip signal") {
    HStack(spacing: HelmSpacing.sm) {
        StatChip(label: "HRV", value: "z +0.5", state: .ready)
        StatChip(label: "Sleep", value: "z -0.2", state: .compromised)
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .signal)
}

#Preview("StatChip instrument") {
    HStack(spacing: HelmSpacing.sm) {
        StatChip(label: "HRV", value: "z +0.5", state: .ready)
        StatChip(label: "Sleep", value: "z -0.2", state: .compromised)
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("StatChip data sheet") {
    HStack(spacing: HelmSpacing.sm) {
        StatChip(label: "HRV", value: "z +0.5", state: .ready)
        StatChip(label: "Sleep", value: "z -0.2", state: .compromised)
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}
