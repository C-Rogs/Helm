import SwiftUI

public struct BriefCard: View {
    private let eyebrow: String
    private let citationLabel: String?
    private let narration: String
    private let isEngineOnly: Bool

    public init(
        eyebrow: String = "Morning Brief",
        citationLabel: String?,
        narration: String,
        isEngineOnly: Bool
    ) {
        self.eyebrow = eyebrow
        self.citationLabel = citationLabel
        self.narration = narration
        self.isEngineOnly = isEngineOnly
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(eyebrow)
                        .helmType(.monoTag, color: HelmColor.fgMuted)

                    Spacer()

                    if let citationLabel {
                        Text(citationLabel)
                            .helmType(.monoTag, color: HelmColor.fgSecondary)
                            .padding(.horizontal, HelmSpacing.xs)
                            .padding(.vertical, HelmSpacing.xxs)
                            .background(HelmColor.surfaceElevated, in: Capsule())
                    }
                }

                Text(narration)
                    .helmType(.body, color: HelmColor.fg)
                    .fixedSize(horizontal: false, vertical: true)

                if isEngineOnly {
                    Text("Engine summary · coach offline")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
    }
}

#Preview("BriefCard instrument") {
    BriefCard(
        citationLabel: "ev-chest-1",
        narration: "ARC 72, balanced. Hit today's compounds at RIR 2. Protein target 150g.",
        isEngineOnly: false
    )
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("BriefCard data sheet") {
    BriefCard(
        citationLabel: "ev-chest-1",
        narration: "ARC 72, balanced. Hit today's compounds at RIR 2. Protein target 150g.",
        isEngineOnly: false
    )
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}
