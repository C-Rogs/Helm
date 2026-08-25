import CoachLLM
import Foundation
import Testing

@Suite("NutritionQueryPayload")
struct NutritionQueryPayloadTests {
    // MARK: - JSON decode per queryType

    @Test("decodes nutrition_query.v1 with today queryType")
    func decodesToday() throws {
        let data = """
        {"schemaVersion":"nutrition_query.v1","queryType":"today"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(NutritionQueryPayload.self, from: data)
        #expect(payload.schemaVersion == "nutrition_query.v1")
        #expect(payload.queryType == .today)
        #expect(payload.helmDay == nil)
        #expect(payload.lookbackDays == nil)
    }

    @Test("decodes nutrition_query.v1 with day queryType and helmDay")
    func decodesDay() throws {
        let data = """
        {"schemaVersion":"nutrition_query.v1","queryType":"day","helmDay":"2026-08-20"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(NutritionQueryPayload.self, from: data)
        #expect(payload.queryType == .day)
        #expect(payload.helmDay == "2026-08-20")
    }

    @Test("decodes nutrition_query.v1 with range queryType and lookbackDays")
    func decodesRange() throws {
        let data = """
        {"schemaVersion":"nutrition_query.v1","queryType":"range","lookbackDays":14}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(NutritionQueryPayload.self, from: data)
        #expect(payload.queryType == .range)
        #expect(payload.lookbackDays == 14)
    }

    @Test("decodes nutrition_query.v1 with weeklyBudget queryType")
    func decodesWeeklyBudget() throws {
        let data = """
        {"schemaVersion":"nutrition_query.v1","queryType":"weeklyBudget"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(NutritionQueryPayload.self, from: data)
        #expect(payload.queryType == .weeklyBudget)
    }

    // MARK: - rawFlexible parsing

    @Test("rawFlexible maps weeklyBudget aliases correctly")
    func rawFlexibleWeeklyBudget() {
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "weeklyBudget") == .weeklyBudget)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "weekly_budget") == .weeklyBudget)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "budget") == .weeklyBudget)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "week") == .weeklyBudget)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "week_ahead") == .weeklyBudget)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "weeklybudget") == .weeklyBudget)
    }

    @Test("rawFlexible maps today aliases")
    func rawFlexibleToday() {
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "today") == .today)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "now") == .today)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "current") == .today)
    }

    @Test("rawFlexible maps day aliases")
    func rawFlexibleDay() {
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "day") == .day)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "onDay") == .day)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "on_day") == .day)
    }

    @Test("rawFlexible maps range aliases")
    func rawFlexibleRange() {
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "range") == .range)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "history") == .range)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "trend") == .range)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "lookback") == .range)
    }

    @Test("rawFlexible returns nil for unknown value")
    func rawFlexibleUnknown() {
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "garbage") == nil)
        #expect(NutritionQueryPayload.QueryType(rawFlexible: "") == nil)
    }

    // Flexible JSON decode uses rawFlexible aliases.
    @Test("decoder accepts flexible queryType values via rawFlexible")
    func decoderAcceptsFlexibleQueryTypes() throws {
        let budgetData = """
        {"schemaVersion":"nutrition_query.v1","queryType":"weekly_budget"}
        """.data(using: .utf8)!
        let budget = try JSONDecoder().decode(NutritionQueryPayload.self, from: budgetData)
        #expect(budget.queryType == .weeklyBudget)

        let historyData = """
        {"schemaVersion":"nutrition_query.v1","queryType":"history","lookbackDays":"14"}
        """.data(using: .utf8)!
        let history = try JSONDecoder().decode(NutritionQueryPayload.self, from: historyData)
        #expect(history.queryType == .range)
        #expect(history.lookbackDays == 14)
    }

    // MARK: - NutritionQueryPayloadParser

    @Test("parser finds nutrition_query.v1 block in text")
    func parserFindsBlock() {
        let text = """
        Here are your nutrition stats.

        {"schemaVersion":"nutrition_query.v1","queryType":"weeklyBudget"}

        Let me know if you want more details.
        """
        let payload = NutritionQueryPayloadParser.parse(from: text)
        #expect(payload?.queryType == .weeklyBudget)
    }

    @Test("parser returns nil for non-matching text")
    func parserReturnsNilForNonMatching() {
        #expect(NutritionQueryPayloadParser.parse(from: "hello world") == nil)
        #expect(NutritionQueryPayloadParser.parse(from: "What should my macros be") == nil)
        #expect(NutritionQueryPayloadParser.parse(from: "") == nil)

        // Wrong schema version.
        let wrongSchema = """
        {"schemaVersion":"trends_query.v1","queryType":"trimp"}
        """
        #expect(NutritionQueryPayloadParser.parse(from: wrongSchema) == nil)
    }

    @Test("parser validates schemaVersion")
    func parserValidatesSchemaVersion() {
        let valid = """
        {"schemaVersion":"nutrition_query.v1","queryType":"today"}
        """
        let validPayload = NutritionQueryPayloadParser.parse(from: valid)
        #expect(validPayload?.queryType == .today)

        let wrong = """
        {"schemaVersion":"meal_query.v1","queryType":"daySummary"}
        """
        #expect(NutritionQueryPayloadParser.parse(from: wrong) == nil)
    }
}