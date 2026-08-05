import Foundation

public struct MemoryAdjustmentPayload: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, Equatable {
        case add
        case clear

        public init?(rawFlexible value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "add", "append", "save", "note":
                self = .add
            case "clear", "resolve", "remove", "done":
                self = .clear
            default:
                return nil
            }
        }
    }

    public let schemaVersion: String
    public let reply: String
    public let action: Action
    public let standingConstraintNote: String?
    public let untilDate: String?
    public let joint: String?
    public let rationale: String?

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.memoryAdjustmentV1.rawValue,
        reply: String,
        action: Action,
        standingConstraintNote: String? = nil,
        untilDate: String? = nil,
        joint: String? = nil,
        rationale: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.action = action
        self.standingConstraintNote = standingConstraintNote
        self.untilDate = untilDate
        self.joint = joint
        self.rationale = rationale
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        reply = try container.decodeIfPresent(String.self, forKey: .reply) ?? ""

        if let decoded = try? container.decode(Action.self, forKey: .action) {
            action = decoded
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .action),
                  let flexible = Action(rawFlexible: raw) {
            action = flexible
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .action,
                in: container,
                debugDescription: "memory_adjustment.v1 action must be add or clear"
            )
        }

        standingConstraintNote = try container.decodeIfPresent(String.self, forKey: .standingConstraintNote)
        untilDate = try container.decodeIfPresent(String.self, forKey: .untilDate)
        joint = try container.decodeIfPresent(String.self, forKey: .joint)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reply
        case action
        case standingConstraintNote
        case untilDate
        case joint
        case rationale
    }
}

public enum MemoryAdjustmentPayloadParser: Sendable {
    public static func parse(from text: String) -> MemoryAdjustmentPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .memoryAdjustmentV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(MemoryAdjustmentPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.memoryAdjustmentV1.rawValue
        else {
            return nil
        }
        switch payload.action {
        case .add:
            let note = payload.standingConstraintNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !note.isEmpty else { return nil }
            return payload
        case .clear:
            return payload
        }
    }

    public static func preview(for payload: MemoryAdjustmentPayload) -> (title: String, detail: String) {
        switch payload.action {
        case .add:
            let note = payload.standingConstraintNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let until = payload.untilDate.map { " until \($0)" } ?? " (default +3 days)"
            return (
                title: "Save to Standing Constraints",
                detail: note + until
            )
        case .clear:
            let joint = payload.joint?.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = (joint?.isEmpty == false) ? joint! : "matching notes"
            return (
                title: "Clear Standing Constraint",
                detail: "Resolve \(label)"
            )
        }
    }
}
