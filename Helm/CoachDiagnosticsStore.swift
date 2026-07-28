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

    private init() {}

    func recordFailure(
        surface: String,
        error: Error,
        requestID: UUID? = nil,
        rejectReason: String? = nil
    ) {
        lastSurface = surface
        lastErrorCode = String(describing: type(of: error))
        lastRequestID = requestID?.uuidString
        lastRejectReason = rejectReason
    }

    func clear() {
        lastErrorCode = nil
        lastRequestID = nil
        lastRejectReason = nil
        lastSurface = nil
    }
}
