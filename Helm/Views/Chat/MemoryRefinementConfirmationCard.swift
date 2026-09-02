import CoachLLM
import DesignSystem
import SwiftUI

/// Card shown in ChatView when the coach has pending memory refinements.
/// Lists each refinement with field name, action badge, proposedValue excerpt, and confidence.
/// Offers "Accept all" and "Dismiss" actions.
struct MemoryRefinementConfirmationCard: View {
    let refinements: [MemoryRefinementEntry]
    let onAcceptAll: () -> Void
    let onDismiss: () -> Void
    @Environment(\.helmTypographyEpoch) private var typographyEpoch

    var body: some View {
        let _ = typographyEpoch
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            HelmSectionEyebrow("COACH LEARNED")

            Text("Coach learned from conversation")
                .helmType(.label, color: HelmColor.fg)

            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                ForEach(Array(refinements.enumerated()), id: \.offset) { _, refinement in
                    refinementRow(refinement)
                }
            }

            HStack(spacing: HelmSpacing.sm) {
                Button("Accept all") {
                    onAcceptAll()
                }
                .buttonStyle(.helmPrimary)

                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.helmSecondary)
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmPanelChrome(.accentQuiet)
    }

    @ViewBuilder
    private func refinementRow(_ entry: MemoryRefinementEntry) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            HStack(spacing: HelmSpacing.xs) {
                Text(fieldLabel(entry.field))
                    .helmType(.monoTag, color: HelmColor.fgSecondary)

                actionBadge(entry.action)

                confidenceBadge(entry.confidence)
            }

            Text(String(entry.proposedValue.prefix(80)))
                .helmType(.body, color: HelmColor.fgSecondary)
                .lineLimit(2)
        }
        .padding(HelmSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }

    @ViewBuilder
    private func actionBadge(_ action: MemoryRefinementEntry.RefinementAction) -> some View {
        Text(action.rawValue)
            .helmType(.monoTag, color: actionBadgeColor(action))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(actionBadgeColor(action).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: MemoryRefinementEntry.RefinementConfidence) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(confidenceColor(confidence))
                .frame(width: 6, height: 6)
            Text(confidence.rawValue)
                .helmType(.monoTag, color: confidenceColor(confidence))
        }
    }

    private func fieldLabel(_ field: String) -> String {
        switch field {
        case "baselinesSummary": return "Baselines"
        case "preferences": return "Preferences"
        case "standingConstraints": return "Constraints"
        case "whatHasWorked": return "What Worked"
        case "injuryHistory": return "Injury History"
        case "trainingResponses": return "Training Responses"
        case "nutritionPatterns": return "Nutrition"
        default: return field
        }
    }

    private func actionBadgeColor(_ action: MemoryRefinementEntry.RefinementAction) -> Color {
        switch action {
        case .add: return HelmColor.ready
        case .merge: return HelmColor.accent
        case .replace: return HelmColor.compromised
        case .remove: return HelmColor.depleted
        }
    }

    private func confidenceColor(_ confidence: MemoryRefinementEntry.RefinementConfidence) -> Color {
        switch confidence {
        case .low: return HelmColor.fgMuted
        case .medium: return HelmColor.compromised
        case .high: return HelmColor.ready
        }
    }
}

#if DEBUG
#Preview("Memory refinement card") {
    VStack {
        MemoryRefinementConfirmationCard(
            refinements: [
                MemoryRefinementEntry(
                    field: "preferences",
                    action: .add,
                    proposedValue: "Prefers push exercises over pull. Likes high volume shoulder work on Tuesdays.",
                    confidence: .high,
                    evidence: [],
                    rationale: "Athlete repeatedly chose push variations."
                ),
                MemoryRefinementEntry(
                    field: "injuryHistory",
                    action: .merge,
                    proposedValue: "Minor right shoulder tightness after heavy OHP.",
                    confidence: .medium,
                    evidence: [],
                    rationale: "Mentioned during session review."
                ),
                MemoryRefinementEntry(
                    field: "whatHasWorked",
                    action: .replace,
                    proposedValue: "AM fasted walks improved recovery HRV by 4 ms.",
                    confidence: .high,
                    evidence: [],
                    rationale: "Athlete described two-week experiment."
                )
            ],
            onAcceptAll: {},
            onDismiss: {}
        )
        .helmScreenPadding()
        .padding()
    }
    .helmTheme()
}
#endif
