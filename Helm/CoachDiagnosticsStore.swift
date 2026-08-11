import Foundation
import Observation

@MainActor
@Observable
final class CoachDiagnosticsStore {
    static let shared = CoachDiagnosticsStore()

    private(set) var lastErrorCode: String?
    private(set) var lastRequestID: String?
    private(set) var lastRejectReason: String?
    private(set) var lastSurface: String?

    /// Accumulated citation-validation failures for the current turn.
    private(set) var citationFailures: [CitationFailure] = []

    struct CitationFailure: Sendable, Equatable {
        let type: CitationFailureType
        let rawTag: String
        let timestamp: Date
    }

    enum CitationFailureType: String, Sendable {
        case phantomEvidence
        case unknownTopic
        case unknownEngine
        case malformedTag
    }

    private init() {}

    func recordFailure(
        surface: String,
        error: Error,
        requestID: UUID? = nil,
        rejectReason: String? = nil
    ) {
        lastSurface = surface
        lastErrorCode = Self.code(for: error)
        lastRequestID = requestID?.uuidString
        lastRejectReason = rejectReason ?? Self.detail(for: error)
    }

    private static func code(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "URLError.\(nsError.code)"
        }
        return "\(nsError.domain):\(nsError.code)"
    }

    private static func detail(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? String(describing: error) : description
    }

    func clear() {
        lastErrorCode = nil
        lastRequestID = nil
        lastRejectReason = nil
        lastSurface = nil
        citationFailures.removeAll()
    }

    func clearTurnState() {
        lastErrorCode = nil
        lastRequestID = nil
        lastRejectReason = nil
        lastSurface = nil
        // Keep citationFailures accumulating.
    }

    func recordCitationFailure(type: CitationFailureType, rawTag: String) {
        citationFailures.append(CitationFailure(type: type, rawTag: rawTag, timestamp: .now))
    }
}
