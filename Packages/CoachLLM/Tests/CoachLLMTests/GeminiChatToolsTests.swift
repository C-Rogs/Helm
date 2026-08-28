import Foundation
import Testing
@testable import CoachLLM

@Suite("Gemini chat tools")
struct GeminiChatToolsTests {
    @Test("catalog writes and queries are declared")
    func declaresCatalogTools() throws {
        let names = GeminiChatTools.functionDeclarations().compactMap { $0["name"] as? String }
        #expect(names == CoachCatalogToolName.allCases.map(\.rawValue))
    }

    @Test("stream body includes tools only when asked")
    func streamBodyToolsFlag() throws {
        let withTools = try GeminiRequestBuilder.streamChatBody(
            systemInstructions: "sys",
            contextBlock: "ctx",
            userMessage: "hi",
            thread: .empty,
            includeCatalogTools: true
        ).encoded()
        let withoutTools = try GeminiRequestBuilder.streamChatBody(
            systemInstructions: "sys",
            contextBlock: "ctx",
            userMessage: "hi",
            thread: .empty,
            includeCatalogTools: false
        ).encoded()

        let withObject = try #require(
            JSONSerialization.jsonObject(with: withTools) as? [String: Any]
        )
        let withoutObject = try #require(
            JSONSerialization.jsonObject(with: withoutTools) as? [String: Any]
        )
        #expect(withObject["tools"] != nil)
        #expect(withObject["toolConfig"] != nil)
        #expect(withoutObject["tools"] == nil)
        #expect(withoutObject["toolConfig"] == nil)
    }

    @Test("functionCall args decode into food_log payload")
    func functionCallDecodesFoodLog() throws {
        let json = """
        {"candidates":[{"content":{"parts":[
          {"text":"Logged lunch."},
          {"functionCall":{"name":"food_log","args":{
            "action":"log",
            "reply":"Logged lunch.",
            "description":"Chicken bowl",
            "bucket":"lunch",
            "caloriesKcal":450,
            "proteinG":35,
            "carbsG":40,
            "fatG":12
          }}}
        ]}}]}
        """
        let calls = GeminiSSEParser.functionCallDeltas(from: json)
        #expect(calls.count == 1)
        #expect(calls[0].name == CoachCatalogToolName.foodLog.rawValue)
        let payload = try calls[0].decode(FoodLogPayload.self, schemaVersion: .foodLogV1)
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.foodLogV1.rawValue)
        #expect(payload.action == .log)
        #expect(payload.caloriesKcal == 450)
        #expect(payload.bucket == "lunch")
    }

    @Test("assembler yields text then complete function call")
    func assemblerYieldsFunctionCallAfterText() async throws {
        let eventJSON = """
        data: {"candidates":[{"content":{"parts":[{"text":"Logged."},{"functionCall":{"name":"food_log","args":{"action":"log","caloriesKcal":200}}}]}}]}
        """
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(eventJSON.utf8))
            continuation.finish()
        }
        var texts: [String] = []
        var calls: [CoachLLMFunctionCall] = []
        for try await event in GeminiStreamAssembler.events(from: stream) {
            switch event {
            case .text(let text): texts.append(text)
            case .functionCall(let call): calls.append(call)
            }
        }
        #expect(texts == ["Logged."])
        #expect(calls.count == 1)
        #expect(calls[0].name == "food_log")
    }

    @Test("functionCall args decode into nutrition_query payload")
    func functionCallDecodesNutritionQuery() throws {
        let json = """
        {"candidates":[{"content":{"parts":[
          {"functionCall":{"name":"nutrition_query","args":{
            "queryType":"weeklyBudget"
          }}}
        ]}}]}
        """
        let calls = GeminiSSEParser.functionCallDeltas(from: json)
        #expect(calls.count == 1)
        let payload = try #require(CoachCatalogQueryDecoder.nutrition(from: calls))
        #expect(payload.queryType == .weeklyBudget)
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.nutritionQueryV1.rawValue)
    }

    @Test("write tool names are not queries")
    func writeVersusQuery() {
        #expect(CoachCatalogToolName.foodLog.isWrite)
        #expect(!CoachCatalogToolName.foodLog.isQuery)
        #expect(CoachCatalogToolName.nutritionQuery.isQuery)
        #expect(!CoachCatalogToolName.nutritionQuery.isWrite)
        let write = CoachLLMFunctionCall(name: "food_log", arguments: ["action": "log"])
        let query = CoachLLMFunctionCall(name: "workout_query", arguments: ["queryType": "latestCompleted"])
        #expect(CoachCatalogToolName.hasWrite(in: [write, query]))
        #expect(!CoachCatalogToolName.hasWrite(in: [query]))
        #expect(!CoachCatalogToolName.chart.isWrite)
        #expect(!CoachCatalogToolName.navigate.isWrite)
        #expect(!CoachCatalogToolName.chart.isQuery)
    }

    @Test("malformed query tool still falls back to JSON")
    func malformedQueryToolFallsBackToJSON() {
        let bad = CoachLLMFunctionCall(name: "nutrition_query", arguments: ["queryType": "not-a-type"])
        let text = """
        Looking up budget.
        {"schemaVersion":"nutrition_query.v1","queryType":"weeklyBudget"}
        """
        let payload = CoachCatalogQueryResolver.resolve(
            named: .nutritionQuery,
            functionCalls: [bad],
            assembledText: text,
            userText: "weekly budget",
            decode: CoachCatalogQueryDecoder.nutrition,
            parseJSON: NutritionQueryPayloadParser.parse,
            infer: { _ in nil }
        )
        #expect(payload?.queryType == .weeklyBudget)
    }

    @Test("functionCall args decode into context_refresh payload")
    func functionCallDecodesContextRefresh() throws {
        let json = """
        {"candidates":[{"content":{"parts":[
          {"functionCall":{"name":"context_refresh","args":{
            "blocks":["nutritionDiary"]
          }}}
        ]}}]}
        """
        let calls = GeminiSSEParser.functionCallDeltas(from: json)
        let payload = try #require(CoachCatalogQueryDecoder.contextRefresh(from: calls))
        #expect(payload.blocks == ["nutritionDiary"])
    }

    @Test("functionCall args decode into chart payload without schemaVersion")
    func functionCallDecodesChart() throws {
        let json = """
        {"candidates":[{"content":{"parts":[
          {"functionCall":{"name":"chart","args":{
            "title":"Hard sets",
            "points":[{"label":"Mon","value":12},{"label":"Tue","value":10}]
          }}}
        ]}}]}
        """
        let calls = GeminiSSEParser.functionCallDeltas(from: json)
        let payload = try #require(CoachCatalogQueryDecoder.chart(from: calls))
        #expect(payload.title == "Hard sets")
        #expect(payload.points.count == 2)
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.chartV1.rawValue)
    }

    @Test("functionCall args decode into navigate payload")
    func functionCallDecodesNavigate() throws {
        let json = """
        {"candidates":[{"content":{"parts":[
          {"functionCall":{"name":"navigate","args":{"tab":"nutrition"}}}
        ]}}]}
        """
        let calls = GeminiSSEParser.functionCallDeltas(from: json)
        let payload = try #require(CoachCatalogQueryDecoder.navigate(from: calls))
        #expect(payload.tab == "nutrition")
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.navigateV1.rawValue)
    }
}
