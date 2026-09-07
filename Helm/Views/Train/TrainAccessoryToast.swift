import DesignSystem
import SwiftUI

/// Ephemeral accessory-bar toast shared by session milestones and (later) rest cues.
struct TrainAccessoryToast: Equatable, Identifiable {
    enum Kind: Equatable {
        case milestone
        case coach
        case restCue
    }

    let id: UUID
    let kind: Kind
    let eyebrow: String
    let title: String
    let message: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        eyebrow: String,
        title: String,
        message: String
    ) {
        self.id = id
        self.kind = kind
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
    }
}

struct TrainAccessoryToastBanner: View {
    let toast: TrainAccessoryToast
    let onDismiss: () -> Void
    var onPrimary: (() -> Void)? = nil
    var primaryLabel: String? = nil

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var presented = false

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(toast.eyebrow)
                    .helmType(.monoTag, color: HelmColor.accent)
                Spacer(minLength: HelmSpacing.xs)
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .helmType(.monoTag, color: HelmColor.fgSecondary)
            }

            Text(toast.title)
                .helmType(.label, color: HelmColor.fg)

            Text(toast.message)
                .helmType(.body, color: HelmColor.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let onPrimary, let primaryLabel {
                Button(primaryLabel, action: onPrimary)
                    .buttonStyle(.helmSecondary)
            }
        }
        .padding(HelmSpacing.md)
        .helmPanelChrome(.accentQuiet)
        .padding(.horizontal, HelmSpacing.screenGutter)
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            )
        )
        .scaleEffect(presented ? 1 : 0.97)
        .opacity(presented ? 1 : 0)
        .onAppear {
            withAnimation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion)) {
                presented = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(toast.eyebrow). \(toast.title). \(toast.message)")
    }
}

#if DEBUG
#Preview("Milestone toast") {
    TrainAccessoryToastBanner(
        toast: TrainAccessoryToast(
            kind: .milestone,
            eyebrow: "MILESTONE",
            title: "Quarter done",
            message: "About 25% through. Check joints and the working muscle."
        ),
        onDismiss: {}
    )
    .padding(.vertical)
    .helmTheme()
}
#endif
