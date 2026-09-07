import DesignSystem
import HealthKitIngest
import Persistence
import SwiftUI

/// Compact Dashboard / trends teaser: top finding headline or warm empty, tap to Patterns.
struct DashboardPatternTeaser: View {
    @State private var patternTeaser: String?

    private var persistence: PersistenceStore { PersistenceBootstrap.persistenceStore }

    var body: some View {
        NavigationLink {
            PatternFindingsView()
        } label: {
            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HStack {
                        HelmSectionEyebrow("PATTERNS")
                        Spacer()
                        HelmIconView(.chevronRight, context: .inline)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                    if let patternTeaser {
                        Text(patternTeaser)
                            .helmType(.label)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Need more days. Associations ship once both arms have at least 12 days.")
                            .helmType(.body, color: HelmColor.fgSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .buttonStyle(.helmPressableCard)
        .accessibilityLabel(patternTeaser.map { "Patterns. \($0)" } ?? "Patterns. Need more days")
        .task {
            await ProactiveBootstrap.refreshPatterns()
            reloadPatternTeaser()
        }
    }

    private func reloadPatternTeaser() {
        let cards = (try? PatternEvaluationService(store: persistence).cardModels()) ?? []
        patternTeaser = cards.first?.headline
    }
}

#Preview("Pattern teaser empty") {
    ScrollView {
        DashboardPatternTeaser()
            .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Pattern teaser instrument") {
    ScrollView {
        DashboardPatternTeaser()
            .helmScreenPadding()
    }
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}
