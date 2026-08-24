import Foundation

#if canImport(Diagnostics)
import Diagnostics
#endif
import os

public typealias CoachLLMSignpostID = OSSignpostID

public enum CoachLLMInstrumentation {
    #if canImport(Diagnostics)
    private static let geminiStream = HelmSignpost(name: .geminiStream, category: .coachLLM)
    #endif

    public static func beginGeminiStream(requestID: UUID) -> CoachLLMSignpostID {
        let signpostID: CoachLLMSignpostID
        #if canImport(Diagnostics)
        signpostID = geminiStream.makeSignpostID()
        geminiStream.begin(id: signpostID)
        #else
        signpostID = OSSignposter().makeSignpostID()
        #endif
        Task { await GeminiStreamTracer.shared.recordBegin(requestID: requestID, name: "GeminiStream") }
        return signpostID
    }

    public static func endGeminiStream(requestID: UUID, signpostID: CoachLLMSignpostID) {
        #if canImport(Diagnostics)
        geminiStream.end(id: signpostID)
        #endif
        _ = signpostID
        Task { await GeminiStreamTracer.shared.recordEnd(requestID: requestID, name: "GeminiStream") }
    }
}
