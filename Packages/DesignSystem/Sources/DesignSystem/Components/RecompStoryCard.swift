import SwiftUI

/// Instrument card for scale-vs-strength / composition dual-signal stories.
public struct RecompStoryCard: View {
    private let story: RecompStory

    public init(story: RecompStory) {
        self.story = story
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text(eyebrow)
                    .helmType(.monoTag, color: HelmColor.fgMuted)

                Text(story.headline)
                    .helmType(story.isEmptyState ? .body : .label, color: HelmColor.fg)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = story.detail {
                    Text(detail)
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .skinAccentStripe(stripeColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var eyebrow: String {
        switch story.kind {
        case .insufficient:
            return "RECOMP"
        case .recompStrength, .recompBodyFat, .recompVolume:
            return "RECOMP"
        case .fatLossFriendly:
            return "CUT SIGNAL"
        case .surplusWorking:
            return "SURPLUS"
        case .scaleSteady, .scaleOnly:
            return "SCALE"
        }
    }

    private var stripeColor: Color {
        switch story.kind {
        case .insufficient, .scaleSteady, .scaleOnly:
            return HelmColor.fgMuted.opacity(0.35)
        case .recompStrength, .recompBodyFat, .recompVolume:
            return HelmColor.accent
        case .fatLossFriendly:
            return HelmColor.ready
        case .surplusWorking:
            return HelmColor.accent.opacity(0.7)
        }
    }

    private var accessibilityText: String {
        if let detail = story.detail {
            return "\(eyebrow). \(story.headline) \(detail)"
        }
        return "\(eyebrow). \(story.headline)"
    }
}

#Preview("Recomp strength") {
    RecompStoryCard(
        story: RecompStory(
            kind: .recompStrength,
            headline: "Scale flat. Strength is climbing.",
            detail: "Body weight held while e1RM moved up. Classic recomp signal."
        )
    )
    .helmScreenPadding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("Warm empty") {
    RecompStoryCard(
        story: RecompStoryClassifier.classify(RecompStorySignals())
    )
    .helmScreenPadding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}
