import Foundation

#if canImport(Diagnostics)
import Diagnostics
import os

public typealias CoachLLMSignpostID = OSSignpostID

public enum CoachLLMInstrumentation {
    public static let geminiStream = HelmSignpost(name: .geminiStream, category: .coachLLM)

    public static func beginGeminiStream(requestID: UUID) -> CoachLLMSignpostID {
        let signpostID = geminiStream.makeSignpostID()
        geminiStream.begin(id: signpostID)
        Task { await GeminiStreamTracer.shared.recordBegin(requestID: requestID, name: "GeminiStream") }
        return signpostID
    }

    public static func endGeminiStream(requestID: UUID, signpostID: CoachLLMSignpostID) {
        geminiStream.end(id: signpostID)
        Task { await GeminiStreamTracer.shared.recordEnd(requestID: requestID, name: "GeminiStream") }
    }
}
#else
public struct CoachLLMSignpostID: Sendable, Hashable {
    public let requestID: UUID

    public init(requestID: UUID) {
        self.requestID = requestID
    }
}

public enum CoachLLMInstrumentation {
    public static func beginGeminiStream(requestID: UUID) -> CoachLLMSignpostID {
        Task { await GeminiStreamTracer.shared.recordBegin(requestID: requestID, name: "GeminiStream") }
        return CoachLLMSignpostID(requestID: requestID)
    }

    public static func endGeminiStream(requestID: UUID, signpostID: CoachLLMSignpostID) {
        _ = signpostID
        Task { await GeminiStreamTracer.shared.recordEnd(requestID: requestID, name: "GeminiStream") }
    }
}
#endif
