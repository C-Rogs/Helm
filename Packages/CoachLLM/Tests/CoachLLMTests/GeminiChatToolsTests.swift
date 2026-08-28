import Foundation
import Testing
@testable import CoachLLM

@Suite("Gemini chat tools")
struct GeminiChatToolsTests {
    @Test("catalog writes are declared")
    func declaresWriteTools() throws {
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
}
