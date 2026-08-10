import CoachLLM
import Core
import Foundation
import Testing

@Suite("ResourceModuleIndex")
struct ResourceModuleIndexTests {
    private static let testDocument: MethodologyDocument = {
        let hypertrophyModule = ResourceModule(
            id: "hypertrophy",
            title: "Hypertrophy",
            description: "Muscle growth science.",
            topicIDs: ["hypertrophy-volume"],
            evidenceIDs: ["ev-hypertrophy-volume", "ev-hypertrophy-frequency"],
            autoAssign: ResourceModuleAutoAssign(always: true)
        )
        let nutritionModule = ResourceModule(
            id: "nutrition",
            title: "Nutrition",
            description: "Sports nutrition evidence.",
            topicIDs: ["nutrition-macros"],
            evidenceIDs: ["ev-nutrition-protein", "ev-nutrition-tdee"],
            autoAssign: ResourceModuleAutoAssign(always: true)
        )
        let strengthModule = ResourceModule(
            id: "strength",
            title: "Strength",
            description: "Performance and periodization.",
            topicIDs: ["strength-periodization"],
            evidenceIDs: ["ev-strength-rpe"],
            autoAssign: ResourceModuleAutoAssign(phases: [.gain], goals: ["strength"], always: false)
        )
        let optionalModule = ResourceModule(
            id: "endurance",
            title: "Endurance",
            description: "Concurrent training.",
            topicIDs: ["endurance-concurrent"],
            evidenceIDs: ["ev-endurance-interference"],
            autoAssign: ResourceModuleAutoAssign(goals: ["cardio"], always: false)
        )
        let noAutoModule = ResourceModule(
            id: "rehab",
            title: "Rehab",
            description: "Pain and return to training.",
            topicIDs: ["rehab-pain-science"],
            evidenceIDs: ["ev-rehab-load-management"],
            autoAssign: nil
        )

        return MethodologyDocument(
            seedVersion: 2,
            placeholder: false,
            modules: [hypertrophyModule, nutritionModule, strengthModule, optionalModule, noAutoModule],
            evidence: [
                EvidenceRecord(id: "ev-hypertrophy-volume", title: "Volume", summary: "Sets drive growth.", citation: "Schoenfeld 2017"),
                EvidenceRecord(id: "ev-hypertrophy-frequency", title: "Frequency", summary: "2x beats 1x.", citation: "Schoenfeld 2016"),
                EvidenceRecord(id: "ev-nutrition-protein", title: "Protein", summary: "1.6 g/kg minimum.", citation: "Morton 2018"),
                EvidenceRecord(id: "ev-nutrition-tdee", title: "TDEE", summary: "Adaptive tracking.", citation: "Hall 2012"),
                EvidenceRecord(id: "ev-strength-rpe", title: "RPE scales", summary: "RIR calibration.", citation: "Helms 2016"),
                EvidenceRecord(id: "ev-endurance-interference", title: "Interference", summary: "AMPK vs mTOR.", citation: "Hawley 2009"),
                EvidenceRecord(id: "ev-rehab-load-management", title: "Load management", summary: "ACWR.", citation: "Gabbett 2016")
            ],
            topics: [
                MethodologyTopic(id: "hypertrophy-volume", title: "Volume", body: "Sets per week.", citationIDs: ["ev-hypertrophy-volume"]),
                MethodologyTopic(id: "nutrition-macros", title: "Macros", body: "Protein and fat.", citationIDs: ["ev-nutrition-protein"]),
                MethodologyTopic(id: "strength-periodization", title: "Periodization", body: "Block vs DUP.", citationIDs: ["ev-strength-rpe"]),
                MethodologyTopic(id: "endurance-concurrent", title: "Concurrent", body: "Session order.", citationIDs: ["ev-endurance-interference"]),
                MethodologyTopic(id: "rehab-pain-science", title: "Pain", body: "Nociception vs pain.", citationIDs: ["ev-rehab-load-management"])
            ]
        )
    }()

    // MARK: - filteredEvidence

    @Test("filteredEvidence returns only records from active module")
    func filteredEvidenceSingleModule() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let evidence = index.filteredEvidence(moduleIDs: ["hypertrophy"])

        let ids = evidence.map(\.id)
        #expect(ids.contains("ev-hypertrophy-volume"))
        #expect(ids.contains("ev-hypertrophy-frequency"))
        #expect(!ids.contains("ev-nutrition-protein"))
        #expect(!ids.contains("ev-strength-rpe"))
    }

    @Test("filteredEvidence with multiple modules returns union")
    func filteredEvidenceMultipleModules() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let evidence = index.filteredEvidence(moduleIDs: ["hypertrophy", "nutrition"])

        let ids = evidence.map(\.id)
        #expect(ids.contains("ev-hypertrophy-volume"))
        #expect(ids.contains("ev-hypertrophy-frequency"))
        #expect(ids.contains("ev-nutrition-protein"))
        #expect(ids.contains("ev-nutrition-tdee"))
        #expect(!ids.contains("ev-strength-rpe"))
    }

    @Test("filteredEvidence with empty module IDs returns empty")
    func filteredEvidenceEmptyModules() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let evidence = index.filteredEvidence(moduleIDs: [])
        #expect(evidence.isEmpty)
    }

    @Test("filteredEvidence handles unknown module IDs gracefully")
    func filteredEvidenceUnknownModule() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let evidence = index.filteredEvidence(moduleIDs: ["nonexistent"])
        #expect(evidence.isEmpty)
    }

    // MARK: - filteredTopics

    @Test("filteredTopics returns only topics from active module")
    func filteredTopicsSingleModule() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let topics = index.filteredTopics(moduleIDs: ["hypertrophy"])

        let ids = topics.map(\.id)
        #expect(ids == ["hypertrophy-volume"])
    }

    @Test("filteredTopics with multiple modules returns union")
    func filteredTopicsMultipleModules() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let topics = index.filteredTopics(moduleIDs: ["hypertrophy", "nutrition"])

        let ids = topics.map(\.id)
        #expect(ids.contains("hypertrophy-volume"))
        #expect(ids.contains("nutrition-macros"))
    }

    // MARK: - moduleSummaries

    @Test("moduleSummaries returns one line per active module")
    func moduleSummaries() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let summary = index.moduleSummaries(moduleIDs: ["hypertrophy", "nutrition"])

        #expect(summary.contains("Hypertrophy"))
        #expect(summary.contains("Muscle growth science"))
        #expect(summary.contains("Nutrition"))
        #expect(summary.contains("Sports nutrition evidence"))
    }

    // MARK: - defaultModuleIDs

    @Test("defaultModuleIDs includes always-true modules")
    func defaultModuleIDsAlways() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let ids = index.defaultModuleIDs(for: nil)

        #expect(ids.contains("hypertrophy"))
        #expect(ids.contains("nutrition"))
        #expect(!ids.contains("strength"))
    }

    @Test("defaultModuleIDs matches phase")
    func defaultModuleIDsPhaseMatch() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let goal = PhaseGoal(phase: .gain)
        let ids = index.defaultModuleIDs(for: goal)

        #expect(ids.contains("hypertrophy"))
        #expect(ids.contains("nutrition"))
        #expect(ids.contains("strength"))
        #expect(!ids.contains("endurance"))
    }

    @Test("defaultModuleIDs matches goal substring")
    func defaultModuleIDsGoalMatch() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let goal = PhaseGoal(phase: .cut, emphasis: "cardio")
        let ids = index.defaultModuleIDs(for: goal)

        #expect(ids.contains("hypertrophy"))
        #expect(ids.contains("nutrition"))
        #expect(ids.contains("endurance"))
        #expect(!ids.contains("strength"))
    }

    @Test("defaultModuleIDs skips modules without autoAssign")
    func defaultModuleIDsNoAutoAssign() {
        let index = ResourceModuleIndex.make(from: Self.testDocument)
        let ids = index.defaultModuleIDs(for: nil)
        #expect(!ids.contains("rehab"))
    }
}
