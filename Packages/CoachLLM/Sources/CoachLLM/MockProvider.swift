import Foundation

public final class MockProvider: CoachLLMProvider, @unchecked Sendable {
    public struct Configuration: Sendable {
        public var availability: ProviderAvailability
        public var responseChunks: [String]
        public var responseError: CoachProviderError?
        public var functionCalls: [CoachLLMFunctionCall]

        public init(
            availability: ProviderAvailability = .available,
            responseChunks: [String] = ["Hello from mock coach."],
            responseError: CoachProviderError? = nil,
            functionCalls: [CoachLLMFunctionCall] = []
        ) {
            self.availability = availability
            self.responseChunks = responseChunks
            self.responseError = responseError
            self.functionCalls = functionCalls
        }
    }

    public let id: String
    public let displayName: String
    public let kind: ProviderKind
    public let requiresNetwork: Bool

    private let lock = NSLock()
    private var configuration: Configuration
    private var _prewarmCount = 0
    private var _resetThreadCount = 0
    private var _lastRequest: RequestSnapshot?

    public struct RequestSnapshot: Sendable, Equatable {
        public let systemInstructions: String
        public let contextBlock: String
        public let userMessage: String
        public let thread: CoachThreadState
    }

    public init(
        id: String = "mock-provider",
        displayName: String = "Mock",
        kind: ProviderKind = .gemini,
        requiresNetwork: Bool = false,
        configuration: Configuration = Configuration()
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.requiresNetwork = requiresNetwork
        self.configuration = configuration
    }

    public func setConfiguration(_ configuration: Configuration) {
        lock.withLock {
            self.configuration = configuration
        }
    }

    public var prewarmCount: Int {
        lock.withLock { _prewarmCount }
    }

    public var resetThreadCount: Int {
        lock.withLock { _resetThreadCount }
    }

    public var lastRequest: RequestSnapshot? {
        lock.withLock { _lastRequest }
    }

    public func availability() async -> ProviderAvailability {
        lock.withLock { configuration.availability }
    }

    public func prewarm() async {
        lock.withLock { _prewarmCount += 1 }
    }

    public func resetThread() async {
        lock.withLock { _resetThreadCount += 1 }
    }

    public func respond(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        freshnessSuffix: String? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let snapshot = RequestSnapshot(
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            userMessage: userMessage,
            thread: thread
        )
        let config = lock.withLock {
            _lastRequest = snapshot
            return configuration
        }

        if let responseError = config.responseError {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: responseError)
            }
        }

        return FixtureStreamHarness.stream(chunks: config.responseChunks)
    }

    public func respondTurn(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        freshnessSuffix: String? = nil
    ) async throws -> AsyncThrowingStream<CoachLLMStreamEvent, Error> {
        let textStream = try await respond(
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            userMessage: userMessage,
            thread: thread,
            freshnessSuffix: freshnessSuffix
        )
        let calls = lock.withLock { configuration.functionCalls }
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in textStream {
                        continuation.yield(.text(chunk))
                    }
                    for call in calls {
                        continuation.yield(.functionCall(call))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
