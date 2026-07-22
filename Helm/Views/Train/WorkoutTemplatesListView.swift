import Core
import DesignSystem
import SwiftUI

struct WorkoutTemplatesListView: View {
    @Bindable var history: WorkoutHistoryController
    let onStartTemplate: (String) -> Void

    @State private var isShowingNamePrompt = false
    @State private var templateName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Templates")
                .font(HelmTypography.headline)
                .foregroundStyle(HelmColor.textPrimary)

            if history.templates.isEmpty {
                Text("Save a finished workout as a template from its detail screen.")
                    .font(HelmTypography.callout)
                    .foregroundStyle(HelmColor.textSecondary)
            } else {
                ForEach(history.templates) { template in
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                                Text(template.name)
                                    .font(HelmTypography.body)
                                    .foregroundStyle(HelmColor.textPrimary)
                                if let notes = template.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(HelmTypography.caption)
                                        .foregroundStyle(HelmColor.textSecondary)
                                }
                            }
                            Spacer()
                            Button("Start") {
                                onStartTemplate(template.id)
                            }
                            .buttonStyle(.helmSecondary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    WorkoutTemplatesListView(history: TrainBootstrap.historyController, onStartTemplate: { _ in })
        .helmTheme()
        .padding()
}
