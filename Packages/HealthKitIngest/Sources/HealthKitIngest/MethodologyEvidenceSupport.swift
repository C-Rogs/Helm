import CoachLLM
import Core
import Foundation

public enum MethodologyEvidenceSupport: Sendable {
    nonisolated(unsafe) private(set) static var recordsByID: [String: EvidenceRecord] = [:]
    nonisolated(unsafe) private(set) static var allRecords: [EvidenceRecord] = []

    public static func configure(with document: MethodologyDocument) {
        recordsByID = MethodologyLibrary.evidenceLookup(from: document)
        allRecords = document.evidence
    }

    public static func records(for ids: [String]) -> [EvidenceRecord] {
        let resolved = ids.compactMap { recordsByID[$0] }
        if !resolved.isEmpty {
            return resolved
        }
        return ids.map { id in
            EvidenceRecord(
                id: id,
                title: id,
                summary: "Referenced by today's prescription.",
                citation: "",
                placeholder: true
            )
        }
    }
}
