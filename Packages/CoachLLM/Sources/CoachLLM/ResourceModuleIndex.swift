import Core
import Foundation
import os

/// Indexes the bundled methodology document for module-aware evidence and topic retrieval.
public enum ResourceModuleIndex: Sendable {
    private static let lock = OSAllocatedUnfairLock<Index?>(initialState: nil)
    public static var shared: Index? { lock.withLock { $0 } }

    public static func configure(with document: MethodologyDocument) {
        lock.withLock { $0 = Index(document: document) }
    }

    /// Callers that already have a document (e.g. tests) can build directly.
    public static func make(from document: MethodologyDocument) -> Index {
        Index(document: document)
    }

    /// Resolved index over one MethodologyDocument.
    public struct Index: Sendable {
        private let modulesByID: [String: ResourceModule]
        private let topicsByID: [String: MethodologyTopic]
        private let evidenceByID: [String: EvidenceRecord]

        public init(document: MethodologyDocument) {
            modulesByID = Dictionary(uniqueKeysWithValues: document.modules.map { ($0.id, $0) })
            topicsByID = Dictionary(uniqueKeysWithValues: document.topics.map { ($0.id, $0) })
            evidenceByID = Dictionary(uniqueKeysWithValues: document.evidence.map { ($0.id, $0) })
        }

        /// Returns the human-readable title for an evidence record, if known.
        public func evidenceTitle(for id: String) -> String? {
            evidenceByID[id]?.title
        }

        /// Returns the human-readable title for a topic, if known.
        public func topicTitle(for id: String) -> String? {
            topicsByID[id]?.title
        }

        /// Union of non-placeholder evidence records for the given module IDs, sorted by ID for stable output.
        public func filteredEvidence(moduleIDs: [String]) -> [EvidenceRecord] {
            var ids = Set<String>()
            for moduleID in moduleIDs {
                guard let module = modulesByID[moduleID] else { continue }
                ids.formUnion(module.evidenceIDs)
            }
            return ids.compactMap { evidenceByID[$0] }
                .filter { !$0.placeholder }
                .sorted { $0.id < $1.id }
        }

        /// Returns the human-readable title for a module ID, if known.
        public func moduleTitle(for moduleID: String) -> String? {
            modulesByID[moduleID]?.title
        }

        /// Union of topics for the given module IDs, sorted by ID.
        public func filteredTopics(moduleIDs: [String]) -> [MethodologyTopic] {
            var ids = Set<String>()
            for moduleID in moduleIDs {
                guard let module = modulesByID[moduleID] else { continue }
                ids.formUnion(module.topicIDs)
            }
            return ids.compactMap { topicsByID[$0] }
                .sorted { $0.id < $1.id }
        }

        /// One line per module: title plus one-sentence description.
        public func moduleSummaries(moduleIDs: [String]) -> String {
            moduleIDs.compactMap { modulesByID[$0] }
                .map { "- \($0.title): \($0.description)" }
                .joined(separator: "\n")
        }

        /// Computes default module IDs from auto-assign rules when the athlete has not explicitly set modules.
        public func defaultModuleIDs(for phaseGoal: PhaseGoal?) -> [String] {
            var ids: [String] = []
            for module in modulesByID.values {
                guard let auto = module.autoAssign else { continue }
                if auto.always {
                    ids.append(module.id)
                    continue
                }
                if let phases = auto.phases, let goal = phaseGoal, phases.contains(goal.phase) {
                    ids.append(module.id)
                    continue
                }
                if let goals = auto.goals, let emphasis = phaseGoal?.emphasis {
                    let lower = emphasis.lowercased()
                    if goals.contains(where: { lower.contains($0.lowercased()) }) {
                        ids.append(module.id)
                    }
                }
            }
            return ids
        }
    }
}
