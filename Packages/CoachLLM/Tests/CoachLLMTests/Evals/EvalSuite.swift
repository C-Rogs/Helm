import CoachLLM
import Foundation
import Testing

@Suite("Golden Scenario Evals")
struct GoldenScenarioEvalSuite {

    @Test("Happy path scenarios pass all assertions")
    func happyPath() async throws {
        let scenarios = EvalScenario.load(fromBundle: .module, category: .happyPath)
        #expect(!scenarios.isEmpty, "No happy path scenarios found")

        for scenario in scenarios {
            let mockResponse = try loadMockResponse(for: scenario, bundle: .module)
            let provider = MockProvider(configuration: .init(responseChunks: [mockResponse]))
            let result = await EvalRunner.run(scenario: scenario, provider: provider, bundle: .module)

            if !result.passed {
                Issue.record("Scenario '\(scenario.id)': \(result.failures.joined(separator: "; "))")
            }
            #expect(result.passed, "Scenario \(scenario.id) failed")
        }
    }

    @Test("Fatigue and deload scenarios enforce no-increase and swap assertions")
    func fatigue() async throws {
        let scenarios = EvalScenario.load(fromBundle: .module, category: .fatigue)
        #expect(!scenarios.isEmpty, "No fatigue scenarios found")

        for scenario in scenarios {
            let mockResponse = try loadMockResponse(for: scenario, bundle: .module)
            let provider = MockProvider(configuration: .init(responseChunks: [mockResponse]))
            let result = await EvalRunner.run(scenario: scenario, provider: provider, bundle: .module)

            if !result.passed {
                Issue.record("Scenario '\(scenario.id)': \(result.failures.joined(separator: "; "))")
            }
            #expect(result.passed, "Scenario \(scenario.id) failed")
        }
    }

    @Test("Safety and injury scenarios enforce exercise swaps and no increases")
    func safety() async throws {
        let scenarios = EvalScenario.load(fromBundle: .module, category: .safety)
        #expect(!scenarios.isEmpty, "No safety scenarios found")

        for scenario in scenarios {
            let mockResponse = try loadMockResponse(for: scenario, bundle: .module)
            let provider = MockProvider(configuration: .init(responseChunks: [mockResponse]))
            let result = await EvalRunner.run(scenario: scenario, provider: provider, bundle: .module)

            if !result.passed {
                Issue.record("Scenario '\(scenario.id)': \(result.failures.joined(separator: "; "))")
            }
            #expect(result.passed, "Scenario \(scenario.id) failed")
        }
    }

    @Test("Nutrition scenarios validate macro estimates within tolerance")
    func nutrition() async throws {
        let scenarios = EvalScenario.load(fromBundle: .module, category: .nutrition)
        #expect(!scenarios.isEmpty, "No nutrition scenarios found")

        for scenario in scenarios {
            let mockResponse = try loadMockResponse(for: scenario, bundle: .module)
            let provider = MockProvider(configuration: .init(responseChunks: [mockResponse]))
            let result = await EvalRunner.run(scenario: scenario, provider: provider, bundle: .module)

            if !result.passed {
                Issue.record("Scenario '\(scenario.id)': \(result.failures.joined(separator: "; "))")
            }
            #expect(result.passed, "Scenario \(scenario.id) failed")
        }
    }

    private func loadMockResponse(for scenario: EvalScenario, bundle: Bundle) throws -> String {
        let resourceName = "golden_response_\(scenario.id)"

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw NSError(domain: "EvalSuite", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing mock response fixture: \(resourceName).json"
            ])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
