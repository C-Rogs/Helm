import Core
import DesignSystem
import SwiftUI

struct MethodologyTopicDetailView: View {
    let topic: MethodologyTopic
    let evidence: [EvidenceRecord]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                Text(topic.title)
                    .font(HelmType.title.font)
                    .foregroundStyle(HelmColor.fg)

                Text(attributedBody)
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !evidence.isEmpty {
                    VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                        Text("CITATIONS")
                            .font(HelmType.monoTag.font)
                            .foregroundStyle(HelmColor.fgMuted)

                        ForEach(evidence) { record in
                            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                                Text(record.title)
                                    .font(HelmType.label.font)
                                    .foregroundStyle(HelmColor.fg)
                                Text(record.summary)
                                    .font(HelmType.body.font)
                                    .foregroundStyle(HelmColor.fgSecondary)
                                if !record.citation.isEmpty {
                                    Text(record.citation)
                                        .font(HelmType.monoTag.font)
                                        .foregroundStyle(HelmColor.fgMuted)
                                }
                            }
                            .padding(HelmSpacing.sm)
                            .background(HelmColor.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))
                        }
                    }
                }
            }
            .padding(HelmSpacing.md)
        }
        .helmScreenBackground()
        .navigationTitle("Methodology")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var attributedBody: AttributedString {
        (try? AttributedString(markdown: topic.body)) ?? AttributedString(topic.body)
    }
}

#Preview {
    NavigationStack {
        MethodologyTopicDetailView(
            topic: MethodologyTopic(
                id: "preview",
                title: "Weekly volume landmarks",
                body: "Helm tracks weekly hard sets per muscle.\n\nThis is coaching guidance, not medical advice.",
                citationIDs: ["ev-volume-landmarks"]
            ),
            evidence: [
                EvidenceRecord(
                    id: "ev-volume-landmarks",
                    title: "Volume landmarks",
                    summary: "MEV to MRV framing.",
                    citation: "Placeholder review",
                    placeholder: true
                )
            ]
        )
    }
    .helmTheme()
}
