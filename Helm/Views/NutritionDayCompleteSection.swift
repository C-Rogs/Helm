import Core
import DesignSystem
import SwiftUI

struct NutritionDayCompleteSection: View {
    let loggingComplete: Bool
    let isSaving: Bool
    let onMarkComplete: () -> Void
    let onReopen: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                if loggingComplete {
                    HStack(spacing: HelmSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(HelmColor.primed)
                        Text("Logging complete")
                            .helmType(.label)
                    }
                    Text("Coach treats today's logged intake as your record.")
                        .helmType(.body, color: HelmColor.fgSecondary)
                    Button("Reopen day") {
                        onReopen()
                    }
                    .buttonStyle(.helmSecondary)
                    .disabled(isSaving)
                } else {
                    Text("Done logging for this day?")
                        .helmType(.label)
                    Text("Mark complete so coach does not treat missing meals as low intake.")
                        .helmType(.body, color: HelmColor.fgSecondary)
                    Button("Mark day complete") {
                        onMarkComplete()
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(isSaving)
                }
            }
        }
    }
}

#Preview("Day complete open") {
    NutritionDayCompleteSection(
        loggingComplete: false,
        isSaving: false,
        onMarkComplete: {},
        onReopen: {}
    )
    .padding()
    .helmTheme()
}

#Preview("Day complete marked") {
    NutritionDayCompleteSection(
        loggingComplete: true,
        isSaving: false,
        onMarkComplete: {},
        onReopen: {}
    )
    .padding()
    .helmTheme()
}
