import SwiftUI

public struct AdjustmentBanner: View {
    public let fromLabel: String
    public let toLabel: String
    public let reason: String
    public let onUndo: () -> Void

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var presented = false

    public init(
        fromLabel: String,
        toLabel: String,
        reason: String,
        onUndo: @escaping () -> Void
    ) {
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.reason = reason
        self.onUndo = onUndo
    }

    public var body: some View {
        HStack(alignment: .top, spacing: HelmSpacing.sm) {
            Image(systemName: "arrow.triangle.swap")
                .font(.body.weight(.semibold))
                .foregroundStyle(HelmColor.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                HStack(spacing: HelmSpacing.xs) {
                    Text(fromLabel)
                        .helmType(.label)
                        .foregroundStyle(HelmColor.fg)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HelmColor.fgMuted)
                    Text(toLabel)
                        .helmType(.label)
                        .foregroundStyle(HelmColor.fg)
                }

                Text(reason)
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("UNDO", action: onUndo)
                .helmType(.monoTag, color: HelmColor.accent)
                .buttonStyle(.plain)
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: HelmRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: HelmRadius.card)
                .stroke(HelmColor.accent.opacity(0.35), lineWidth: 1)
        )
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            )
        )
        .scaleEffect(presented ? 1 : 0.96)
        .opacity(presented ? 1 : 0)
        .onAppear {
            withAnimation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion)) {
                presented = true
            }
        }
        .animation(
            HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: reduceMotion),
            value: fromLabel
        )
    }
}

#Preview("Adjustment banner") {
    AdjustmentBanner(
        fromLabel: "Cable Fly",
        toLabel: "DB Fly",
        reason: "Cable station is taken; swap to dumbbells."
    ) {}
    .padding()
    .helmTheme()
}
