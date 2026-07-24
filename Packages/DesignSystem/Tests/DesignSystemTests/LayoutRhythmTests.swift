import Foundation
import Testing
@testable import DesignSystem

@Suite("Layout rhythm")
struct LayoutRhythmTests {
    @Test("spacing scale matches DESIGN-SYSTEM section 5")
    func spacingScale() {
        #expect(HelmSpacing.xxs == 4)
        #expect(HelmSpacing.xs == 8)
        #expect(HelmSpacing.sm == 12)
        #expect(HelmSpacing.md == 16)
        #expect(HelmSpacing.lg == 22)
        #expect(HelmSpacing.xl == 32)
        #expect(HelmSpacing.screenGutter == HelmSpacing.lg)
    }

    @Test("layout dimensions derive from spacing scale")
    func layoutDimensions() {
        #expect(HelmLayout.chartHeight == HelmSpacing.sm * 15)
        #expect(HelmLayout.emptyChartMinHeight == HelmSpacing.sm * 10)
        #expect(HelmLayout.arcReadoutMaxWidth == HelmSpacing.lg * 10)
        #expect(HelmChartStyle.standardHeight == HelmLayout.chartHeight)
    }

    @Test("audited views avoid raw spacing literals")
    func auditedViewsAvoidRawSpacingLiterals() throws {
        let repoRoot = layoutRhythmRepoRoot()
        let auditedRelativePaths = [
            "Helm/Views/DashboardView.swift",
            "Helm/Views/DashboardTrendsSection.swift",
            "Helm/Views/ThresholdInsightCard.swift",
            "Helm/Views/TrainView.swift",
            "Helm/Views/Train/ExerciseSectionView.swift",
            "Helm/Views/Train/PersonalRecordsCelebrationView.swift",
            "Helm/Views/Train/WorkoutHistoryListView.swift",
            "Helm/Views/Train/WorkoutTemplatesListView.swift",
            "Helm/Views/Train/WorkoutSessionDetailView.swift",
            "Helm/Views/Train/WorkoutImportPreviewView.swift",
            "Helm/Views/Train/WorkoutImportPreviewView.swift",
            "Helm/Views/TrendsView.swift",
            "Helm/Views/Trends/TrendWeightChartCard.swift",
            "Helm/Views/Trends/ReadinessHistoryChartCard.swift",
            "Helm/Views/Trends/E1RMProgressionChartCard.swift",
            "Helm/Views/Trends/MuscleVolumeBarChartCard.swift",
            "Helm/Views/Trends/EnergyBalanceChartCard.swift",
            "Helm/Views/Trends/TrendsChartShared.swift",
            "Helm/Views/NutritionView.swift",
            "Helm/Views/NutritionDaySummaryCard.swift",
            "Helm/Views/SettingsView.swift",
            "Helm/Views/MemoryProfileEditorView.swift",
            "Helm/Views/SchemaV2ExportView.swift"
        ]

        let forbiddenPatterns = [
            #"spacing:\s*[1-9]\d*"#,
            #"padding\(\s*[1-9]\d*\s*\)"#,
            #"\.padding\(\.(top|bottom|leading|trailing|horizontal|vertical),\s*[1-9]\d*\s*\)"#
        ]

        for relativePath in auditedRelativePaths {
            let url = repoRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("spacing: 0") { continue }
                if trimmed.contains(", 0)") || trimmed.contains("(0)") { continue }

                for pattern in forbiddenPatterns {
                    let regex = try Regex(pattern)
                    if trimmed.firstMatch(of: regex) != nil {
                        Issue.record("Raw spacing literal in \(relativePath):\(index + 1): \(trimmed)")
                    }
                }
            }
        }
    }

    @Test("audited views avoid nested Card surfaces")
    func auditedViewsAvoidNestedCards() throws {
        let repoRoot = layoutRhythmRepoRoot()
        let auditedRelativePaths = [
            "Helm/Views/DashboardView.swift",
            "Helm/Views/NutritionDaySummaryCard.swift",
            "Helm/Views/Train/WorkoutHistoryListView.swift",
            "Helm/Views/Train/WorkoutTemplatesListView.swift",
            "Helm/Views/Train/WorkoutSessionDetailView.swift",
            "Helm/Views/Train/WorkoutImportPreviewView.swift",
            "Helm/Views/SettingsView.swift"
        ]

        for relativePath in auditedRelativePaths {
            let url = repoRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            if sourceContainsNestedCard(source) {
                Issue.record("Nested Card in \(relativePath)")
            }
        }
    }

    private func sourceContainsNestedCard(_ source: String) -> Bool {
        var searchStart = source.startIndex

        while searchStart < source.endIndex {
            guard let cardRange = source.range(of: "Card", range: searchStart..<source.endIndex) else {
                break
            }

            var braceIndex = cardRange.upperBound
            while braceIndex < source.endIndex, source[braceIndex].isWhitespace {
                braceIndex = source.index(after: braceIndex)
            }

            guard braceIndex < source.endIndex, source[braceIndex] == "{" else {
                searchStart = cardRange.upperBound
                continue
            }

            guard let closeIndex = matchingClosingBrace(in: source, openingBrace: braceIndex) else {
                break
            }

            let interiorStart = source.index(after: braceIndex)
            let interior = source[interiorStart..<closeIndex]
            if interior.contains("Card {") || interior.contains("Card{") {
                return true
            }

            searchStart = closeIndex
        }

        return false
    }

    private func matchingClosingBrace(in source: String, openingBrace: String.Index) -> String.Index? {
        guard source[openingBrace] == "{" else { return nil }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = source.index(after: index)
        }

        return nil
    }

    private func layoutRhythmRepoRoot() -> URL {
        let fileURL = URL(fileURLWithPath: #filePath)
        return fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
