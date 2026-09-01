import SwiftUI

public struct SessionDesignedCard<Content: View>: View {
    public let title: String
    public let summary: String
    public let rationale: [String]
    /// Leading chip label (Train: Discuss; legacy: Coach).
    public let leadingChipTitle: String
    public let onLeadingChip: () -> Void
    public let onRegenerate: () -> Void
    public let showsRegenerate: Bool
    public let onView: (() -> Void)?
    @ViewBuilder public let content: () -> Content

    public init(
        title: String,
        summary: String,
        rationale: [String],
        leadingChipTitle: String = "Discuss",
        onLeadingChip: @escaping () -> Void,
        onRegenerate: @escaping () -> Void,
        onView: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.rationale = rationale
        self.leadingChipTitle = leadingChipTitle
        self.onLeadingChip = onLeadingChip
        self.onRegenerate = onRegenerate
        self.showsRegenerate = true
        self.onView = onView
        self.content = content
    }

    /// Without regenerate chip.
    public init(
        title: String,
        summary: String,
        rationale: [String],
        leadingChipTitle: String = "Discuss",
        onLeadingChip: @escaping () -> Void,
        onView: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.rationale = rationale
        self.leadingChipTitle = leadingChipTitle
        self.onLeadingChip = onLeadingChip
        self.onRegenerate = {}
        self.showsRegenerate = false
        self.onView = onView
        self.content = content
    }

    /// Compatibility for call sites that still name the leading action Coach.
    public init(
        title: String,
        summary: String,
        rationale: [String],
        onCoach: @escaping () -> Void,
        onRegenerate: @escaping () -> Void,
        onView: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            summary: summary,
            rationale: rationale,
            leadingChipTitle: "Discuss",
            onLeadingChip: onCoach,
            onRegenerate: onRegenerate,
            onView: onView,
            content: content
        )
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack(alignment: .top, spacing: HelmSpacing.md) {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text(title)
                            .helmType(.title)
                        Text(summary)
                            .helmType(.body, color: HelmColor.fgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: HelmSpacing.xs) {
                        sessionChip(title: leadingChipTitle, action: onLeadingChip)
                        if let onView {
                            sessionChip(title: "View", action: onView)
                        }
                        if showsRegenerate {
                            sessionChip(title: "Regenerate", action: onRegenerate)
                        }
                    }
                    .layoutPriority(1)
                }

                if !rationale.isEmpty {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        ForEach(rationale, id: \.self) { line in
                            Text(line)
                                .helmType(.body, color: HelmColor.fgMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                content()
            }
        }
    }

    private func sessionChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .helmType(.monoTag, color: HelmColor.accent)
                .padding(.horizontal, HelmSpacing.sm)
                .padding(.vertical, HelmSpacing.xxs)
                .background(HelmColor.accent.opacity(0.12), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(HelmColor.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.helmPressable)
    }
}

public struct SessionExercisePreviewList: View {
    public let exercises: [String]
    public let collapsedVisibleCount: Int

    public init(exercises: [String], collapsedVisibleCount: Int = 2) {
        self.exercises = exercises
        self.collapsedVisibleCount = collapsedVisibleCount
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            ForEach(visibleExercises, id: \.self) { name in
                Text(name)
                    .helmType(.body)
            }
            if hiddenCount > 0 {
                Text("+\(hiddenCount) more")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
    }

    private var visibleExercises: [String] {
        Array(exercises.prefix(collapsedVisibleCount))
    }

    private var hiddenCount: Int {
        max(0, exercises.count - collapsedVisibleCount)
    }
}

#Preview("Session designed card") {
    SessionDesignedCard(
        title: "Pull",
        summary: "Back + Biceps · 16 sets · week 3 accumulating",
        rationale: [],
        onLeadingChip: {},
        onView: {}
    ) {
        SessionExercisePreviewList(
            exercises: [
                "Bent Over Row (Barbell)",
                "Lat Pulldown (Cable)",
                "Barbell Curl"
            ],
            collapsedVisibleCount: 3
        )
    }
    .padding()
    .helmTheme()
}

#Preview("Session designed card long summary") {
    SessionDesignedCard(
        title: "Arm Focus",
        summary: "Biceps + Triceps + Shoulders · 3 sets · week 1 accumulating · Emphasis: Arms",
        rationale: [
            "Biceps: 0/6 hard sets this week."
        ],
        onCoach: {},
        onRegenerate: {}
    ) {
        SessionExercisePreviewList(exercises: ["Bent Over Row (Barbell)"])
    }
    .padding()
    .helmTheme()
    .dynamicTypeSize(.accessibility5)
}