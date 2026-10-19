import Core
import DesignSystem
import ReadinessKit
import SwiftUI

struct IllnessEarlyWarningCard: View {
    let warning: IllnessEarlyWarning

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Early warning")
                    .helmType(.monoTag, color: HelmColor.fgMuted)

                Text(warning.message)
                    .helmType(.body, color: HelmColor.fg)

                Text(signalLabels.uppercased())
                    .helmType(.monoTag, color: HelmColor.compromised)
            }
        }
        .skinAccentStripe(HelmColor.compromised.opacity(0.45))
    }

    private var signalLabels: String {
        warning.signals.map(\.label).joined(separator: " · ")
    }
}

#Preview("Illness early warning") {
    IllnessEarlyWarningCard(
        warning: IllnessEarlyWarning(
            id: "preview",
            helmDay: HelmDay(year: 2026, month: 7, day: 30),
            signals: [.hrv, .restingHeartRate],
            message: "Body looks strained (HRV and resting HR). Consider taking it easy. Wellness signal only, not a diagnosis."
        )
    )
    .helmScreenPadding()
    .helmTheme()
}
