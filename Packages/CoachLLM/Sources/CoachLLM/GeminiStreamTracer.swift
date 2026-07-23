import Foundation

public actor GeminiStreamTracer {
    public struct Span: Sendable, Equatable {
        public let requestID: UUID
        public let name: String
        public let began: Bool
        public let ended: Bool
    }

    public static let shared = GeminiStreamTracer()

    private var spans: [UUID: Span] = [:]

    public func reset() {
        spans = [:]
    }

    public func recordBegin(requestID: UUID, name: String) {
        let existing = spans[requestID]
        spans[requestID] = Span(
            requestID: requestID,
            name: name,
            began: true,
            ended: existing?.ended ?? false
        )
    }

    public func recordEnd(requestID: UUID, name: String) {
        let existing = spans[requestID]
        spans[requestID] = Span(
            requestID: requestID,
            name: name,
            began: existing?.began ?? true,
            ended: true
        )
    }

    public func completedSpans() -> [Span] {
        spans.values.sorted { $0.requestID.uuidString < $1.requestID.uuidString }
    }
}
