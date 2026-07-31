import CoachLLM
import Core
import Foundation
import HealthKitIngest

enum CoachChatActionKind: Sendable, Equatable {
    case workoutStart(WorkoutStartPayload)
    case foodLog(FoodLogPayload)
}

struct CoachChatActionProposal: Sendable, Equatable, Identifiable {
    let id: UUID
    let reply: String
    let kind: CoachChatActionKind
    let title: String
    let detail: String
    let reason: String?
    let confirmLabel: String
    let cancelLabel: String

    init(
        id: UUID = UUID(),
        reply: String,
        kind: CoachChatActionKind,
        title: String,
        detail: String,
        reason: String? = nil,
        confirmLabel: String,
        cancelLabel: String
    ) {
        self.id = id
        self.reply = reply
        self.kind = kind
        self.title = title
        self.detail = detail
        self.reason = reason
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
    }
}

enum CoachChatActionParser {
    static func proposal(from text: String) -> CoachChatActionProposal? {
        if let payload = FoodLogPayloadParser.parse(from: text) {
            let preview = FoodLogCommandPreview.preview(for: payload)
            let confirmLabel: String
            switch payload.action {
            case .log: confirmLabel = "Log meal"
            case .edit: confirmLabel = "Update meal"
            case .delete: confirmLabel = "Delete meal"
            }
            return CoachChatActionProposal(
                reply: payload.reply,
                kind: .foodLog(payload),
                title: preview.title,
                detail: preview.detail,
                reason: payload.reply,
                confirmLabel: confirmLabel,
                cancelLabel: "Cancel"
            )
        }

        if let payload = WorkoutStartPayloadParser.parse(from: text) {
            let preview = WorkoutStartCommandPreview.preview(for: payload)
            let stripped = CoachChatTextFormatter.userFacingText(from: text)
            let reply = stripped.isEmpty
                ? "Ready when you are. Confirm to start \(preview.title)."
                : stripped
            return CoachChatActionProposal(
                reply: reply,
                kind: .workoutStart(payload),
                title: preview.title,
                detail: preview.detail,
                reason: preview.reason,
                confirmLabel: "Start workout",
                cancelLabel: "Not yet"
            )
        }

        return nil
    }
}

enum CoachChatDisplayText {
    static func assistantText(from assembled: String, pendingAction: CoachChatActionProposal?) -> String {
        let stripped = CoachChatTextFormatter.userFacingText(from: assembled)
        if !stripped.isEmpty {
            return stripped
        }
        if let pendingAction, !pendingAction.reply.isEmpty {
            return pendingAction.reply
        }
        return stripped
    }
}

enum WorkoutStartCommandPreview {
    static func preview(for payload: WorkoutStartPayload) -> (title: String, detail: String, reason: String?) {
        if payload.hasDetailedSets {
            let names = payload.exercises?.map(\.name).joined(separator: ", ") ?? "Custom session"
            return (
                title: payload.title ?? "Start workout",
                detail: names,
                reason: "Starts the discussed session with prescribed sets."
            )
        }

        if let labels = payload.exercises?.map(\.name), !labels.isEmpty {
            return (
                title: "Start today's workout",
                detail: labels.joined(separator: " → "),
                reason: "Reorders and starts today's prescription."
            )
        }

        let adjusted = payload.useAdjustedPrescription == true
        return (
            title: "Start today's workout",
            detail: adjusted ? "Coach-adjusted prescription" : "Engine prescription",
            reason: adjusted ? "Uses the plan adjusted earlier in chat." : nil
        )
    }
}
