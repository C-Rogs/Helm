import Foundation

#if canImport(Diagnostics)
import Diagnostics
#endif

enum InSessionCoachDiagnostics {
    static func recordPropose(
        sessionID: String,
        requestID: UUID?,
        opCount: Int,
        status: String,
        rejectReason: String?,
        schemaVersion: String
    ) async {
        var context: [String: String] = [
            "sessionID": sessionID,
            "opCount": String(opCount),
            "status": status,
            "schemaVersion": schemaVersion
        ]
        if let requestID {
            context["requestID"] = requestID.uuidString
        }
        if let rejectReason {
            context["rejectReason"] = rejectReason
        }

        #if canImport(Diagnostics)
        await DiagnosticsLog.shared.record(
            category: .coachLLM,
            level: .info,
            message: "InSessionCoachPropose",
            context: context
        )
        #endif
    }
}
