import Foundation
import Testing
@testable import Core

@Suite("RestingHeartRateDisplay")
struct RestingHeartRateDisplayTests {
    @Test("fresh value shows Apple Health subtitle and full emphasis")
    func freshValuePresentation() {
        let presentation = RestingHeartRateDisplay.contributorPresentation(
            hasValue: true,
            isStale: false
        )

        #expect(presentation.subtitle == "from Apple Health")
        #expect(presentation.isValueMuted == false)
    }

    @Test("stale value keeps subtitle and mutes emphasis")
    func staleValuePresentation() {
        let presentation = RestingHeartRateDisplay.contributorPresentation(
            hasValue: true,
            isStale: true
        )

        #expect(presentation.subtitle == "from Apple Health")
        #expect(presentation.isValueMuted == true)
    }

    @Test("missing value has no subtitle")
    func missingValuePresentation() {
        let presentation = RestingHeartRateDisplay.contributorPresentation(
            hasValue: false,
            isStale: false
        )

        #expect(presentation.subtitle == nil)
        #expect(presentation.isValueMuted == false)
    }

    @Test("live workout heart rate is not referenced on recovery or dashboard views")
    func liveHeartRateTrainOnly() throws {
        let repoRoot = helmRepoRoot()
        let auditedPaths = [
            "Helm/Views/DashboardView.swift",
            "Helm/Views/RecoveryDetailView.swift",
            "Helm/Views/RecoveryDetailContainer.swift",
            "Helm/RecoveryDetailBuilder.swift"
        ]

        for relativePath in auditedPaths {
            let url = repoRoot.appendingPathComponent(relativePath)
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(
                !source.contains("latestLiveHeartRateBPM"),
                "Unexpected live workout HR reference in \(relativePath)"
            )
            #expect(
                !source.contains("liveHeartRateBPM"),
                "Unexpected live workout HR reference in \(relativePath)"
            )
        }
    }

    private func helmRepoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
