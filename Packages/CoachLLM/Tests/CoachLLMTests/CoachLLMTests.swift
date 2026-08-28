import Foundation
import Testing
@testable import CoachLLM

@Suite("TokenBudget")
struct TokenBudgetTests {
    @Test("provider token caps match the plan")
    func providerCaps() {
        #expect(TokenBudget.maxInputTokens(for: .gemini) == 48_000)
        #expect(TokenBudget.maxInputTokens(for: .foundationModels) == 4_096)
        #expect(TokenBudget.maxInputTokens(for: .openRouter) == 32_000)
    }

    @Test("chars per token estimator rounds up")
    func estimateTokens() {
        #expect(TokenBudget.estimateTokens(characterCount: 0) == 0)
        #expect(TokenBudget.estimateTokens(characterCount: 1) == 1)
        #expect(TokenBudget.estimateTokens(characterCount: 4) == 2)
        #expect(TokenBudget.estimateTokens(characterCount: 7) == 2)
        #expect(TokenBudget.estimateTokens(characterCount: 8) == 3)
    }

    @Test("character budget subtracts reserved tokens")
    func characterBudget() {
        let budget = TokenBudget.characterBudget(for: .foundationModels, reservedTokens: 1_000)
        #expect(budget == Int(Double(3_096) * TokenBudget.charsPerToken))
    }
}

@Suite("CoachFailurePolicy")
struct CoachFailurePolicyTests {
    @Test("typed provider errors map to engine-only states")
    func providerErrors() {
        let cases: [(CoachProviderError, CoachDegradedReason)] = [
            (.rateLimited, .rateLimited),
            (.timeout, .timeout),
            (.offline, .offline),
            (.unavailable("No key"), .providerUnavailable),
            (.contextTooLarge, .contextTooLarge),
            (.cancelled, .cancelled),
            (.requestFailed("boom"), .other)
        ]

        for (error, expectedReason) in cases {
            let state = CoachFailurePolicy.degradedState(for: error)
            #expect(state.mode == .engineOnly)
            #expect(state.reason == expectedReason)
            #expect(!state.userMessage.isEmpty)
        }
    }

    @Test("url errors map to offline, timeout, or connection detail")
    func urlErrors() {
        let offline = CoachFailurePolicy.degradedState(for: URLError(.notConnectedToInternet))
        #expect(offline.reason == .offline)
        #expect(offline.userMessage.contains("offline"))

        let timeout = CoachFailurePolicy.degradedState(for: URLError(.timedOut))
        #expect(timeout.reason == .timeout)
        #expect(timeout.userMessage.contains("timed out"))

        let unreachable = CoachFailurePolicy.degradedState(for: URLError(.cannotFindHost))
        #expect(unreachable.reason == .timeout)
        #expect(unreachable.userMessage.contains("couldn't reach Gemini"))

        let tls = CoachFailurePolicy.degradedState(for: URLError(.secureConnectionFailed))
        #expect(tls.reason == .other)
        #expect(tls.userMessage.contains("securely"))
        #expect(!tls.userMessage.lowercased().contains("unavailable"))
    }

    @Test("unknown errors still degrade to engine-only")
    func unknownErrors() {
        struct SampleFailure: Error {}
        let state = CoachFailurePolicy.degradedState(for: SampleFailure())
        #expect(state.mode == .engineOnly)
        #expect(state.reason == .other)
        #expect(state.userMessage.contains("request failed"))
        #expect(state.userMessage.contains("SampleFailure"))
        #expect(!state.userMessage.lowercased().contains("unavailable"))
    }
}

@MainActor
@Suite("ProviderRegistry")
struct ProviderRegistryTests {
    @Test("registry reuses one instance per backend")
    func reuseInstances() {
        let registry = ProviderRegistry()
        let firstGemini = registry.provider(for: .gemini)
        let secondGemini = registry.provider(for: .gemini)
        let foundation = registry.provider(for: .foundationModels)
        let openRouter = registry.provider(for: .openRouter)

        #expect(firstGemini.id == secondGemini.id)
        #expect(foundation.id == "foundation-models")
        #expect(openRouter.id == "openrouter-disabled")
    }

    @Test("reserved slots stay unavailable in v1")
    func reservedUnavailable() async {
        let registry = ProviderRegistry()

        let foundation = await registry.provider(for: .foundationModels).availability()
        let openRouter = await registry.provider(for: .openRouter).availability()

        #expect(foundation.isAvailable == false)
        #expect(openRouter.isAvailable == false)
    }

    @Test("gemini install replaces placeholder")
    func installGemini() {
        let registry = ProviderRegistry()
        let placeholder = registry.provider(for: .gemini)
        #expect(placeholder.id == "gemini-placeholder")

        let mock = MockProvider(id: "gemini-live")
        registry.installGeminiProvider(mock)
        #expect(registry.provider(for: .gemini).id == "gemini-live")
    }
}

@Suite("MockProvider")
struct MockProviderTests {
    @Test("mock provider exercises the full protocol")
    func fullProtocol() async throws {
        let provider = MockProvider(
            configuration: MockProvider.Configuration(
                responseChunks: ["A", "B", "C"]
            )
        )

        #expect(await provider.availability().isAvailable)

        await provider.prewarm()
        #expect(provider.prewarmCount == 1)

        let stream = try await provider.respond(
            systemInstructions: "system",
            contextBlock: "context",
            userMessage: "hello",
            thread: CoachThreadState(messages: [
                CoachMessage(role: .user, text: "prior")
            ]),
            freshnessSuffix: nil
        )

        let text = try await FixtureStreamHarness.reassemble(stream)
        #expect(text == "ABC")
        #expect(provider.lastRequest?.userMessage == "hello")
        #expect(provider.lastRequest?.thread.isFollowUp == false)

        let call = CoachLLMFunctionCall(
            name: CoachCatalogToolName.foodLog.rawValue,
            arguments: ["action": "log", "caloriesKcal": 200]
        )
        provider.setConfiguration(
            MockProvider.Configuration(
                responseChunks: ["Logged."],
                functionCalls: [call]
            )
        )
        let turn = try await provider.respondTurn(
            systemInstructions: "system",
            contextBlock: "context",
            userMessage: "log lunch",
            thread: .empty,
            freshnessSuffix: nil
        )
        var texts: [String] = []
        var calls: [CoachLLMFunctionCall] = []
        for try await event in turn {
            switch event {
            case .text(let chunk): texts.append(chunk)
            case .functionCall(let functionCall): calls.append(functionCall)
            }
        }
        #expect(texts == ["Logged."])
        #expect(calls.map(\.name) == [CoachCatalogToolName.foodLog.rawValue])

        await provider.resetThread()
        #expect(provider.resetThreadCount == 1)
    }

    @Test("mock provider surfaces configured failures")
    func configuredFailure() async throws {
        let provider = MockProvider(
            configuration: MockProvider.Configuration(responseError: .rateLimited)
        )

        let stream = try await provider.respond(
            systemInstructions: "",
            contextBlock: "",
            userMessage: "ping",
            thread: .empty,
            freshnessSuffix: nil
        )

        do {
            _ = try await FixtureStreamHarness.reassemble(stream)
            Issue.record("Expected rate limit error")
        } catch let error as CoachProviderError {
            let state = CoachFailurePolicy.degradedState(for: error)
            #expect(state.reason == .rateLimited)
        }
    }
}

@Suite("FixtureStreamHarness")
struct FixtureStreamHarnessTests {
    @Test("fixture chunks load and reassemble")
    func fixtureRoundTrip() async throws {
        let chunks = try FixtureStreamHarness.loadChunks(named: "mock_stream_chunks", bundle: Bundle.module)
        let stream = FixtureStreamHarness.stream(chunks: chunks)
        let text = try await FixtureStreamHarness.reassemble(stream)
        #expect(text == "Readiness is moderate today. Keep volume steady.")
    }
}
