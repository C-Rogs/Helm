import SwiftUI

public struct StatChip: View {
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
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HelmSpacing.sm)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }

    private var valueColor: Color {
        if let state {
            return HelmColor.color(for: state)
        }
        return HelmColor.fg
    }
}

#Preview("StatChip") {
    HStack(spacing: HelmSpacing.sm) {
        StatChip(label: "HRV", value: "z +0.5", state: .ready)
        StatChip(label: "Sleep", value: "z -0.2", state: .compromised)
    }
    .padding()
    .helmTheme()
}
