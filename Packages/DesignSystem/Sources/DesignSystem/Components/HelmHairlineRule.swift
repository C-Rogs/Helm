import SwiftUI

/// A 1pt hairline divider. Replaces nested card surfaces for in-section separation.
public struct HelmHairlineRule: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(HelmColor.hairline)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

/// A list or in-card row separated by a top hairline instead of a nested card.
public struct HelmRuledRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HelmHairlineRule()
            content
                .padding(.vertical, HelmSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Hairline rule") {
    VStack(spacing: HelmSpacing.md) {
        Text("Section above")
            .helmType(.label)
        HelmHairlineRule()
        Text("Section below")
            .helmType(.body, color: HelmColor.fgSecondary)
    }
    .padding()
    .helmTheme()
}

#Preview("Ruled row instrument") {
    Card {
        VStack(spacing: 0) {
            Text("Primary metric")
                .helmType(.bigNumber)
                .padding(.bottom, HelmSpacing.md)
            HelmRuledRow {
                StatChip(label: "HRV", value: "z +0.5", state: .ready)
            }
            HelmRuledRow {
                StatChip(label: "Sleep", value: "z -0.2", state: .compromised)
            }
        }
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("Ruled row data sheet") {
    Card {
        VStack(spacing: 0) {
            Text("Primary metric")
                .helmType(.bigNumber)
                .padding(.bottom, HelmSpacing.md)
            HelmRuledRow {
                StatChip(label: "HRV", value: "z +0.5", state: .ready)
            }
        }
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}
