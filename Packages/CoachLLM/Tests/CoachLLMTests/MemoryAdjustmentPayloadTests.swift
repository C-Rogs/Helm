import CoachLLM
import Foundation
import Testing

@Suite("MemoryAdjustmentPayload")
struct MemoryAdjustmentPayloadTests {
    @Test("decodes add fixture")
    func decodesAdd() throws {
        let json = """
        {"schemaVersion":"memory_adjustment.v1","reply":"Saved.","action":"add","standingConstraintNote":"Shoulder niggle","untilDate":"2026-08-08","joint":"shoulder"}
        """
        let payload = try JSONDecoder().decode(MemoryAdjustmentPayload.self, from: Data(json.utf8))
        #expect(payload.action == .add)
        #expect(payload.standingConstraintNote == "Shoulder niggle")
        #expect(payload.untilDate == "2026-08-08")
        #expect(payload.joint == "shoulder")
    }

    @Test("parses embedded block from coach text")
    func parsesEmbedded() {
        let text = """
        I'll keep overhead pressing soft-paused for a few days.
        {"schemaVersion":"memory_adjustment.v1","reply":"Confirm to save.","action":"add","standingConstraintNote":"Avoid OHP","joint":"shoulder"}
        """
        let payload = MemoryAdjustmentPayloadParser.parse(from: text)
        #expect(payload?.action == .add)
        #expect(payload?.standingConstraintNote == "Avoid OHP")
    }

    @Test("rejects add without note")
    func rejectsEmptyNote() {
        let text = """
        {"schemaVersion":"memory_adjustment.v1","reply":"Nope","action":"add","standingConstraintNote":"  "}
        """
        #expect(MemoryAdjustmentPayloadParser.parse(from: text) == nil)
    }

    @Test("decodes clear action")
    func decodesClear() throws {
        let json = """
        {"schemaVersion":"memory_adjustment.v1","reply":"Cleared.","action":"resolve","joint":"shoulder"}
        """
        let payload = try JSONDecoder().decode(MemoryAdjustmentPayload.self, from: Data(json.utf8))
        #expect(payload.action == .clear)
        #expect(payload.joint == "shoulder")
    }
}
