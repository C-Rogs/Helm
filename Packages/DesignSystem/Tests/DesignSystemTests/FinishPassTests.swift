import Foundation
import Testing
@testable import DesignSystem

@Suite("Finish pass")
struct FinishPassTests {
    @Test("icon catalog documents every case")
    func iconCatalogCompleteness() {
        #expect(HelmIcon.allCases.count >= 20)
        #expect(HelmIcon.dashboard.rawValue == "gauge.with.dots.needle.67percent")
    }

    @Test("icon contexts use distinct sizes")
    func iconContextSizes() {
        #expect(HelmIconContext.tab.pointSize > HelmIconContext.inline.pointSize)
        #expect(HelmIconContext.action.pointSize > HelmIconContext.section.pointSize)
    }

    @Test("shipped screens avoid em and en dashes in user-facing strings")
    func noDashPunctuationInAppCopy() throws {
        let repoRoot = finishPassRepoRoot()
        let auditedRelativePaths = [
            "Helm/Views/DashboardView.swift",
            "Helm/Views/DashboardTrendsSection.swift",
            "Helm/Views/TrainView.swift",
            "Helm/Views/TrendsView.swift",
            "Helm/Views/NutritionView.swift",
            "Helm/Views/ChatView.swift",
            "Helm/Views/SettingsView.swift",
            "Helm/Views/Train/WorkoutHistoryListView.swift",
            "Helm/RootTabView.swift",
            "Packages/DesignSystem/Sources/DesignSystem/Components/HelmScreenState.swift",
            "Packages/DesignSystem/Sources/DesignSystem/Components/BriefCard.swift",
            "Packages/DesignSystem/Sources/DesignSystem/Components/AskCoachBar.swift"
        ]

        for relativePath in auditedRelativePaths {
            let url = repoRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                if trimmed.contains("\u{2014}") || trimmed.contains("\u{2013}") {
                    Issue.record("Dash punctuation in \(relativePath):\(index + 1): \(trimmed)")
                }
            }
        }
    }

    @Test("interactive surfaces use pressable button styles")
    func interactiveSurfacesUsePressableStyles() throws {
        let repoRoot = finishPassRepoRoot()
        let auditedRelativePaths = [
            "Helm/Views/DashboardView.swift",
            "Helm/Views/TrainView.swift",
            "Helm/Views/Train/WorkoutHistoryListView.swift",
            "Helm/Views/Train/ExerciseSectionView.swift",
            "Helm/Views/ChatView.swift",
            "Helm/Views/NutritionView.swift",
            "Packages/DesignSystem/Sources/DesignSystem/Components/SetRow.swift",
            "Packages/DesignSystem/Sources/DesignSystem/Components/AskCoachBar.swift",
            "Packages/DesignSystem/Sources/DesignSystem/Components/ExplainableAffordance.swift",
            "Packages/DesignSystem/Sources/DesignSystem/Components/AdjustmentBanner.swift"
        ]

        for relativePath in auditedRelativePaths {
            let url = repoRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.range(of: #"\.buttonStyle\(\.plain\)"#, options: .regularExpression) != nil {
                Issue.record("Plain button style without press feedback in \(relativePath)")
            }
        }
    }

    @Test("primary screens declare empty loading and error previews")
    func screenStatePreviews() throws {
        let repoRoot = finishPassRepoRoot()
        let expectations: [(path: String, markers: [String])] = [
            ("Helm/Views/DashboardView.swift", ["#Preview(\"Dashboard loading\")", "#Preview(\"Dashboard empty", "#Preview(\"Dashboard error\")"]),
            ("Helm/Views/TrainView.swift", ["#Preview(\"Train empty\")", "#Preview(\"Train loading\")", "#Preview(\"Train error\")"]),
            ("Helm/Views/TrendsView.swift", ["#Preview(\"Trends loading\")", "#Preview(\"Trends error\")", "#Preview(\"Trends empty"]),
            ("Helm/Views/NutritionView.swift", ["#Preview(\"Nutrition loading\")", "#Preview(\"Nutrition empty\")", "#Preview(\"Nutrition error\")"]),
            ("Helm/Views/ChatView.swift", ["#Preview(\"Chat empty\")", "#Preview(\"Chat loading\")", "#Preview(\"Chat error\")"])
        ]

        for expectation in expectations {
            let url = repoRoot.appendingPathComponent(expectation.path)
            let source = try String(contentsOf: url, encoding: .utf8)
            for marker in expectation.markers {
                if !source.contains(marker) {
                    Issue.record("Missing preview marker \(marker) in \(expectation.path)")
                }
            }
        }
    }

    private func finishPassRepoRoot() -> URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
