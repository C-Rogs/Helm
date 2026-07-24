import SwiftUI

public struct StatChip: View {
    @Environment(\.helmSkin) private var skin

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
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(chipPadding)
        .background(chipBackground)
        .overlay(chipOverlay)
    }

    private var chipPadding: EdgeInsets {
        switch skin {
        case .dataSheet:
            EdgeInsets(top: HelmSpacing.sm, leading: 0, bottom: HelmSpacing.sm, trailing: 0)
        default:
            EdgeInsets(top: HelmSpacing.sm, leading: HelmSpacing.sm, bottom: HelmSpacing.sm, trailing: HelmSpacing.sm)
        }
    }

    @ViewBuilder
    private var chipBackground: some View {
        switch skin {
        case .dataSheet:
            Color.clear
        default:
            HelmColor.surfaceElevated
                .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
    }

    @ViewBuilder
    private var chipOverlay: some View {
        switch skin {
        case .dataSheet:
            VStack {
                Spacer()
                Rectangle()
                    .fill(HelmColor.hairline)
                    .frame(height: 1)
            }
        default:
            EmptyView()
        }
    }

    private var valueColor: Color {
        if let state {
            return HelmColor.color(for: state)
        }
        return HelmColor.fg
    }
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
