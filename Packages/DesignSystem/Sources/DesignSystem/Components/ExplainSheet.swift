import SwiftUI

public struct ExplainSheet: View {
    private let metric: ExplainableMetric
    private let onAskCoach: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    public init(
        metric: ExplainableMetric,
        onAskCoach: ((String) -> Void)? = nil
    ) {
        self.metric = metric
        self.onAskCoach = onAskCoach
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    heroSection
                    contributorsSection

                    if !metric.isCoachHandoffEnabled {
                        Text("Engine contributors only · coach offline")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }

                    if metric.isCoachHandoffEnabled {
                        Button {
                            onAskCoach?(metric.coachPromptSeed)
                            dismiss()
                        } label: {
                            Label("Ask coach about this", systemImage: "bubble.left.and.bubble.right")
                        }
                        .buttonStyle(.helmPrimary)
                    }
                }
                .padding(HelmSpacing.screenGutter)
            }
            .helmScreenBackground()
            .navigationTitle("Show your working")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            HapticEngine.shared.play(.selection)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.domain)
                    .helmType(.monoTag, color: HelmColor.fgMuted)

                Spacer()

                if let citation = metric.citation {
                    Text(citation.label)
                        .helmType(.monoTag, color: HelmColor.fgSecondary)
                        .padding(.horizontal, HelmSpacing.xs)
                        .padding(.vertical, HelmSpacing.xxs)
                        .background(HelmColor.surfaceElevated, in: Capsule())
                        .accessibilityLabel("Citation \(citation.id)")
                }
            }

            Text(metric.title)
                .helmType(.label)

            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
                Text(metric.value)
                    .helmType(.heroNumber, color: heroColor)
                if let unit = metric.unit {
                    Text(unit)
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }

            if let state = metric.state {
                Text(state.label)
                    .helmType(.monoTag, color: HelmColor.color(for: state))
            }

            if let summary = metric.summary, !summary.isEmpty {
                Text(summary)
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Contributors")
                .helmType(.label)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: HelmSpacing.sm),
                    GridItem(.flexible(), spacing: HelmSpacing.sm),
                ],
                spacing: HelmSpacing.sm
            ) {
                ForEach(metric.contributors) { contributor in
                    StatChip(
                        label: contributor.label,
                        value: contributor.value,
                        state: contributor.state
                    )
                }
            }

            if metric.contributors.contains(where: { $0.detail != nil }) {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    ForEach(metric.contributors) { contributor in
                        if let detail = contributor.detail, !detail.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
                                Text(contributor.label)
                                    .helmType(.body, color: HelmColor.fgSecondary)
                                Spacer(minLength: HelmSpacing.sm)
                                Text(detail)
                                    .helmType(.body, color: HelmColor.fgMuted)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    private var heroColor: Color {
        if let state = metric.state {
            return HelmColor.color(for: state)
        }
        return HelmColor.fg
    }
}

#Preview("ExplainSheet readiness") {
    ExplainSheet(metric: .readinessFixture)
}
