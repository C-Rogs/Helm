import CoachLLM
import Core
import Foundation

struct EvalScenario: Codable {
    var id: String
    var title: String
    var category: String
    var contextDays: CoachContextDays
    var userPrompt: String
    var expectedBounds: ExpectedBounds
    var expectedCitations: [String]
    var mustNotIncrease: Bool
    var mustSwapExercise: Bool
    var macroTolerancePercent: Double?
}

struct ExpectedBounds: Codable {
    var maxSetDelta: Int?
    var maxLoadDeltaKg: Double?
    var mustContainKind: [String]?
    var mustNotContainKind: [String]?
    var minCaloriesKcal: Double?
    var maxCaloriesKcal: Double?
    var minProteinG: Double?
    var maxProteinG: Double?
    var phaseConstraint: String?
}

enum EvalScenarioCategory: String, CaseIterable {
    case happyPath
    case fatigue
    case safety
    case nutrition
}

extension EvalScenario {
    private static let scenarioNames: [EvalScenarioCategory: [String]] = [
        .happyPath: [
            "happyPath_normal_day",
            "happyPath_progress_boost",
            "happyPath_rest_day",
            "happyPath_maintenance"
        ],
        .fatigue: [
            "fatigue_low_hrv_sleep_debt",
            "fatigue_high_trimp",
            "fatigue_accumulated_week",
            "fatigue_pending_reactive_deload",
            "fatigue_compensated"
        ],
        .safety: [
            "safety_shoulder_pain",
            "safety_knee_pain",
            "safety_extreme_fatigue",
            "safety_beginner_overload"
        ],
        .nutrition: [
            "nutrition_deficit",
            "nutrition_surplus_cut",
            "nutrition_protein_ok",
            "nutrition_meal_estimate"
        ]
    ]

    static func load(fromBundle bundle: Bundle = .module, category: EvalScenarioCategory) -> [EvalScenario] {
        guard let names = scenarioNames[category] else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var scenarios: [EvalScenario] = []
        for name in names {
            let resourceName = "golden_\(name)"
            guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let scenario = try? decoder.decode(EvalScenario.self, from: data) else {
                continue
            }
            scenarios.append(scenario)
        }
        return scenarios.sorted { $0.id < $1.id }
    }

    static func loadAll(fromBundle bundle: Bundle = .module) -> [EvalScenario] {
        EvalScenarioCategory.allCases.flatMap { load(fromBundle: bundle, category: $0) }
    }
}