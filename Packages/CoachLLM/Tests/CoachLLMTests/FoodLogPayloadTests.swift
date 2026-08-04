import CoachLLM
import Foundation
import Testing

@Suite("FoodLogPayload")
struct FoodLogPayloadTests {
    @Test("decodes food_log.v1 log fixture")
    func decodesLogFixture() throws {
        let json = try fixtureText(named: "food_log_v1_log")
        let payload = try JSONDecoder().decode(FoodLogPayload.self, from: Data(json.utf8))
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.foodLogV1.rawValue)
        #expect(payload.action == FoodLogPayload.Action.log)
        #expect(payload.description == "Chicken rice bowl")
        #expect(payload.bucket == "lunch")
        #expect(payload.caloriesKcal == 450)
        #expect(payload.proteinG == 35)
    }

    @Test("parses embedded food_log block from assistant text")
    func parsesEmbeddedBlock() throws {
        let text = """
        Logged.
        {"schemaVersion":"food_log.v1","reply":"Logged lunch.","action":"log","description":"Salad","bucket":"lunch","caloriesKcal":320}
        """
        let block = try #require(
            CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .foodLogV1)
        )
        let payload = try JSONDecoder().decode(FoodLogPayload.self, from: Data(block.utf8))
        #expect(payload.action == FoodLogPayload.Action.log)
        #expect(payload.caloriesKcal == 320)
    }

    @Test("strips food_log JSON from assistant text")
    func stripsJSONFromChatText() {
        let text = """
        Logged lunch.
        {"schemaVersion":"food_log.v1","reply":"Logged lunch.","action":"log","bucket":"lunch","caloriesKcal":320}
        """
        let display = CoachChatTextFormatter.userFacingText(from: text)
        #expect(display == "Logged lunch.")
    }

    @Test("decodes resilient food_log variants from model noise")
    func decodesResilientVariants() throws {
        let json = """
        {"schemaVersion":"food_log.v1","action":"add","description":"Gin and tonic","bucket":"snacks","caloriesKcal":"180","proteinG":"0","carbsG":12,"fatG":0}
        """
        let payload = try JSONDecoder().decode(FoodLogPayload.self, from: Data(json.utf8))
        #expect(payload.action == .log)
        #expect(payload.reply.isEmpty)
        #expect(payload.description == "Gin and tonic")
        #expect(payload.caloriesKcal == 180)
        #expect(payload.proteinG == 0)
        #expect(payload.carbsG == 12)
    }

    @Test("decodes food_log with ingredient items")
    func decodesItems() throws {
        let json = """
        {"schemaVersion":"food_log.v1","reply":"Logged breakfast.","action":"log","description":"Eggs and toast","bucket":"breakfast","caloriesKcal":350,"proteinG":18,"carbsG":30,"fatG":14,"items":[{"name":"egg","estimatedGrams":100,"confidence":"medium"},{"name":"toast","estimatedGrams":40,"confidence":"medium"}]}
        """
        let payload = try JSONDecoder().decode(FoodLogPayload.self, from: Data(json.utf8))
        #expect(payload.hasIngredientBreakdown)
        #expect(payload.items?.count == 2)
        #expect(payload.items?.first?.name == "egg")
    }

    private func fixtureText(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            Issue.record("Missing fixture \(name).json")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
