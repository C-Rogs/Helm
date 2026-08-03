import SwiftUI

/// Mini arc-plus-trace mark for section eyebrows and tab-adjacent labels.
public struct HelmArcTraceMark: View {
    public init() {}

    public var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(HelmColor.hairline, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(135))

            Path { path in
                path.move(to: CGPoint(x: 2, y: 8))
                path.addLine(to: CGPoint(x: 5, y: 5))
                path.addLine(to: CGPoint(x: 9, y: 7))
            }
            .stroke(HelmColor.accent, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

/// Uppercase mono eyebrow for card and section headers.
public struct HelmSectionEyebrow: View {
    private let text: String
    private let showsArcMark: Bool

    public init(_ text: String, showsArcMark: Bool = true) {
        self.text = text
        self.showsArcMark = showsArcMark
    }

    public var body: some View {
        HStack(spacing: HelmSpacing.xs) {
            if showsArcMark {
                HelmArcTraceMark()
            }
            Text(text)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Honest empty copy for list and screen surfaces.
public struct HelmEmptyState: View {
    private let title: String
    private let message: String
    private let icon: HelmIcon?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        title: String,
        message: String,
        icon: HelmIcon? = .empty,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            if let icon {
                HelmIconView(icon, context: .section)
                    .foregroundStyle(HelmColor.fgMuted)
            }

            Text(title)
                .helmType(.title)

            Text(message)
                .helmType(.body, color: HelmColor.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.helmSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, HelmSpacing.md)
    }
}

/// Recoverable failure copy for screen-level errors.
public struct HelmErrorState: View {
    private let title: String
    private let message: String
    private let retryTitle: String?
    private let onRetry: (() -> Void)?

    public init(
        title: String = "Something went wrong",
        message: String,
        retryTitle: String? = "Try again",
        onRetry: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(spacing: HelmSpacing.sm) {
                    HelmIconView(.error, context: .inline)
                        .foregroundStyle(HelmColor.depleted)
                    HelmSectionEyebrow("ERROR", showsArcMark: false)
                }

                Text(title)
                    .helmType(.label)

                Text(message)
                    .helmType(.body, color: HelmColor.depleted)
                    .fixedSize(horizontal: false, vertical: true)

                if let retryTitle, let onRetry {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(.helmSecondary)
                }
            }
        }
    }
}

/// Skeleton placeholder for screen-level loading.
public struct HelmLoadingState: View {
    private let rowCount: Int

    public init(rowCount: Int = 3) {
        self.rowCount = rowCount
    }

    public var body: some View {
        HelmSkeletonCard(rowCount: rowCount)
            .accessibilityLabel("Loading")
    }
}

#Preview("Screen states instrument") {
    ScrollView {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            HelmSectionEyebrow("MORNING BRIEF")
            HelmEmptyState(
                title: "Ask why",
                message: "Coach answers from your readiness, training, and nutrition data.",
                icon: .chat
            )
            HelmLoadingState(rowCount: 2)
            HelmErrorState(message: "Could not load trends.", onRetry: {})
        }
        .padding()
    }
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("Screen states data sheet") {
    ScrollView {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            HelmSectionEyebrow("TODAY'S SESSION")
            HelmEmptyState(
                title: "No workouts yet",
                message: "Finish a session to see history here.",
                icon: .train
            )
            HelmErrorState(message: "Export failed.", onRetry: {})
        }
        .padding()
    }
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}

#Preview("Screen states accessibility") {
    HelmEmptyState(
        title: "Awaiting data",
        message: "Connect HealthKit and let Signal build your baseline.",
        icon: .health
    )
    .padding()
    .helmTheme()
    .dynamicTypeSize(.accessibility5)
}
