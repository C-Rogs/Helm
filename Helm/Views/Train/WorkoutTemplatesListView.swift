import Core
import DesignSystem
import SwiftUI

struct WorkoutTemplatesListView: View {
    @Bindable var history: WorkoutHistoryController
    let onStartTemplate: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Templates")
                .helmType(.label)

            if history.templates.isEmpty {
                Text("Save today's prescription or a finished workout as a reusable template.")
                    .helmType(.body, color: HelmColor.fgSecondary)
            } else {
                Card {
                    VStack(spacing: 0) {
                        ForEach(history.templates) { template in
                            HelmRuledRow {
                                HStack(alignment: .center, spacing: HelmSpacing.sm) {
                                    NavigationLink {
                                        WorkoutTemplateDetailView(
                                            history: history,
                                            templateID: template.id,
                                            onStart: { onStartTemplate(template.id) }
                                        )
                                    } label: {
                                        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                                            Text(template.name)
                                                .helmType(.body)
                                            if let notes = template.notes, !notes.isEmpty {
                                                Text(notes)
                                                    .helmType(.body, color: HelmColor.fgSecondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)

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
    NavigationStack {
        WorkoutTemplatesListView(history: TrainBootstrap.historyController, onStartTemplate: { _ in })
            .helmScreenPadding()
    }
    .helmTheme()
}
