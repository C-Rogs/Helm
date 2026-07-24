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
                .helmType(.label)

            if history.templates.isEmpty {
                Text("Save a finished workout as a template from its detail screen.")
                    .helmType(.body, color: HelmColor.fgSecondary)
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(history.templates) { template in
                            HelmRuledRow {
                                HStack(alignment: .center, spacing: HelmSpacing.sm) {
                                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                                        Text(template.name)
                                            .helmType(.body)
                                        if let notes = template.notes, !notes.isEmpty {
                                            Text(notes)
                                                .helmType(.body, color: HelmColor.fgSecondary)
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
    }
}

#Preview {
    WorkoutTemplatesListView(history: TrainBootstrap.historyController, onStartTemplate: { _ in })
        .helmScreenPadding()
        .helmTheme()
}
