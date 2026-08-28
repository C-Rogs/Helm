import CoachLLM
import Core
import Foundation
import HealthKitIngest

enum CoachChatActionKind: Sendable, Equatable {
    case workoutStart(WorkoutStartPayload)
    case foodLog(FoodLogPayload)
    case mealCopy(MealCopyPayload)
    case memoryAdjustment(MemoryAdjustmentPayload)
    case settingsAdjustment(SettingsAdjustmentPayload)
    case reactiveDeload(ReactiveDeloadPayload)
    case planRegenerate(PlanRegeneratePayload)
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
    static func proposal(
        from text: String,
        functionCalls: [CoachLLMFunctionCall] = []
    ) -> CoachChatActionProposal? {
        if let fromTools = proposal(fromFunctionCalls: functionCalls, visibleText: text) {
            return fromTools
        }
        if CoachCatalogToolName.hasWrite(in: functionCalls) {
            return nil
        }
        return proposal(fromJSONText: text)
    }

    static func foodLogPayload(from functionCalls: [CoachLLMFunctionCall]) -> FoodLogPayload? {
        decodeFirst(FoodLogPayload.self, named: .foodLog, from: functionCalls)
    }

    static func hasMalformedFoodLogCall(_ functionCalls: [CoachLLMFunctionCall]) -> Bool {
        functionCalls.contains { $0.name == CoachCatalogToolName.foodLog.rawValue }
            && foodLogPayload(from: functionCalls) == nil
    }

    static func workoutStartPayload(from functionCalls: [CoachLLMFunctionCall]) -> WorkoutStartPayload? {
        decodeFirst(WorkoutStartPayload.self, named: .workoutStart, from: functionCalls)
            ?? decodeFirst(
                WorkoutStartPayload.self,
                named: .workoutStart,
                schema: .workoutStartV1,
                from: functionCalls
            )
    }

    private static func proposal(
        fromFunctionCalls calls: [CoachLLMFunctionCall],
        visibleText: String
    ) -> CoachChatActionProposal? {
        for call in calls {
            if let proposal = proposal(from: call, visibleText: visibleText) {
                return proposal
            }
        }
        return nil
    }

    private static func proposal(
        from call: CoachLLMFunctionCall,
        visibleText: String
    ) -> CoachChatActionProposal? {
        switch CoachCatalogToolName(rawValue: call.name) {
        case .foodLog:
            guard let payload = try? call.decode(FoodLogPayload.self, schemaVersion: .foodLogV1) else {
                return nil
            }
            return proposal(fromFoodLog: payload)
        case .mealCopy:
            guard let payload = try? call.decode(MealCopyPayload.self, schemaVersion: .mealCopyV1) else {
                return nil
            }
            return proposal(fromMealCopy: payload)
        case .memoryAdjustment:
            guard let payload = try? call.decode(
                MemoryAdjustmentPayload.self,
                schemaVersion: .memoryAdjustmentV1
            ), isValidMemoryAdjustment(payload) else {
                return nil
            }
            return proposal(fromMemory: payload)
        case .workoutStart:
            guard let payload = workoutStartPayload(from: [call]) else { return nil }
            return proposal(fromWorkoutStart: payload, visibleText: visibleText)
        case .settingsAdjustment:
            guard let payload = try? call.decode(
                SettingsAdjustmentPayload.self,
                schemaVersion: .settingsAdjustmentV1
            ) else {
                return nil
            }
            return proposal(fromSettings: payload, visibleText: visibleText)
        case .reactiveDeload:
            guard let payload = try? call.decode(
                ReactiveDeloadPayload.self,
                schemaVersion: .reactiveDeloadV1
            ) else {
                return nil
            }
            return proposal(fromDeload: payload)
        case .planRegenerate:
            guard let payload = try? call.decode(
                PlanRegeneratePayload.self,
                schemaVersion: .planRegenerateV1
            ) else {
                return nil
            }
            return proposal(fromPlanRegenerate: payload)
        case .mealQuery, .recoveryQuery, .calendarQuery, .trendsQuery, .workoutQuery, .nutritionQuery:
            return nil
        case nil:
            return nil
        }
    }

    private static func isValidMemoryAdjustment(_ payload: MemoryAdjustmentPayload) -> Bool {
        switch payload.action {
        case .add:
            let note = payload.standingConstraintNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !note.isEmpty
        case .clear:
            return true
        }
    }

    private static func decodeFirst<Payload: Decodable>(
        _ type: Payload.Type,
        named name: CoachCatalogToolName,
        schema: CoachOutputSchemaVersion? = nil,
        from calls: [CoachLLMFunctionCall]
    ) -> Payload? {
        let version = schema ?? name.schemaVersion
        for call in calls where call.name == name.rawValue {
            if let payload = try? call.decode(type, schemaVersion: version) {
                return payload
            }
        }
        return nil
    }

    static func proposal(fromJSONText text: String) -> CoachChatActionProposal? {
        if let payload = FoodLogPayloadParser.parse(from: text) {
            return proposal(fromFoodLog: payload)
        }

        if let payload = MealCopyPayloadParser.parse(from: text) {
            return proposal(fromMealCopy: payload)
        }

        if let payload = MemoryAdjustmentPayloadParser.parse(from: text) {
            return proposal(fromMemory: payload)
        }

        if let payload = WorkoutStartPayloadParser.parse(from: text) {
            return proposal(fromWorkoutStart: payload, visibleText: text)
        }

        if let payload = SettingsAdjustmentPayloadParser.parse(from: text) {
            return proposal(fromSettings: payload, visibleText: text)
        }

        if let payload = ReactiveDeloadPayloadParser.parse(from: text) {
            return proposal(fromDeload: payload)
        }

        if let payload = PlanRegeneratePayloadParser.parse(from: text) {
            return proposal(fromPlanRegenerate: payload)
        }

        return nil
    }

    private static func proposal(fromFoodLog payload: FoodLogPayload) -> CoachChatActionProposal {
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

    private static func proposal(fromMealCopy payload: MealCopyPayload) -> CoachChatActionProposal {
        let preview = MealCopyCommandApplier.preview(for: payload)
        return CoachChatActionProposal(
            reply: payload.reply,
            kind: .mealCopy(payload),
            title: preview.title,
            detail: preview.detail,
            reason: payload.reply,
            confirmLabel: "Copy meal",
            cancelLabel: "Cancel"
        )
    }

    private static func proposal(fromMemory payload: MemoryAdjustmentPayload) -> CoachChatActionProposal {
        let preview = MemoryAdjustmentPayloadParser.preview(for: payload)
        let confirmLabel: String
        switch payload.action {
        case .add: confirmLabel = "Save to Memory"
        case .clear: confirmLabel = "Clear constraint"
        }
        return CoachChatActionProposal(
            reply: payload.reply,
            kind: .memoryAdjustment(payload),
            title: preview.title,
            detail: preview.detail,
            reason: payload.rationale ?? payload.reply,
            confirmLabel: confirmLabel,
            cancelLabel: "Cancel"
        )
    }

    private static func proposal(
        fromWorkoutStart payload: WorkoutStartPayload,
        visibleText: String
    ) -> CoachChatActionProposal {
        let preview = WorkoutStartCommandPreview.preview(for: payload)
        let stripped = CoachChatTextFormatter.userFacingText(from: visibleText)
        let reply = stripped.isEmpty
            ? "Confirm to start \(preview.title)."
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

    private static func proposal(
        fromSettings payload: SettingsAdjustmentPayload,
        visibleText: String
    ) -> CoachChatActionProposal {
        let preview = SettingsAdjustmentPreview.preview(for: payload)
        let stripped = CoachChatTextFormatter.userFacingText(from: visibleText)
        let reply = stripped.isEmpty
            ? "Settings updated."
            : stripped
        return CoachChatActionProposal(
            reply: reply,
            kind: .settingsAdjustment(payload),
            title: preview.title,
            detail: preview.detail,
            reason: payload.rationale ?? payload.reply,
            confirmLabel: "Apply",
            cancelLabel: "Cancel"
        )
    }

    private static func proposal(fromDeload payload: ReactiveDeloadPayload) -> CoachChatActionProposal {
        let label = payload.action == .confirm ? "Confirm deload" : "Dismiss deload"
        let title = payload.action == .confirm ? "Take a deload week" : "Skip deload"
        let detail = payload.action == .confirm
            ? "Engine proposes a full-week deload for recovery."
            : "Continue training as scheduled."
        return CoachChatActionProposal(
            reply: payload.reply,
            kind: .reactiveDeload(payload),
            title: title,
            detail: detail,
            reason: payload.reply,
            confirmLabel: label,
            cancelLabel: "Cancel"
        )
    }

    private static func proposal(fromPlanRegenerate payload: PlanRegeneratePayload) -> CoachChatActionProposal {
        CoachChatActionProposal(
            reply: payload.reply,
            kind: .planRegenerate(payload),
            title: "Regenerate today's plan",
            detail: "Clears today's prescription and re-plans from the engine.",
            reason: payload.reply,
            confirmLabel: "Regenerate",
            cancelLabel: "Cancel"
        )
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
        // Structured-only turn with empty reply: keep a short line so the transcript
        // does not drop the assistant row before the confirmation card.
        if let pendingAction {
            switch pendingAction.kind {
            case .workoutStart:
                return "Confirm to start \(pendingAction.title)."
            case .foodLog, .mealCopy, .memoryAdjustment, .settingsAdjustment, .reactiveDeload, .planRegenerate:
                return pendingAction.title
            }
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
                title: payload.title ?? "Start today's workout",
                detail: labels.joined(separator: " → "),
                reason: "Reorders and starts today's prescription."
            )
        }

        let adjusted = payload.useAdjustedPrescription == true
        return (
            title: "Start today's workout",
            detail: adjusted
                ? "Coach-adjusted prescription (confirm shows engine order)"
                : "Today's engine prescription (confirm to open Train)",
            reason: adjusted
                ? "Uses the plan adjusted earlier in chat. Open Train if the exercise list looks wrong."
                : "Starts the engine prescription for today. Negotiate a custom list in chat first if you want different exercises."
        )
    }
}

enum SettingsAdjustmentPreview {
    static func preview(for payload: SettingsAdjustmentPayload) -> (title: String, detail: String, reason: String?) {
        var parts: [String] = []
        if let phase = payload.phase {
            parts.append("Phase: \(phase)")
        }
        if let rate = payload.weeklyRateKg {
            parts.append("Rate: \(String(format: "%.1f", rate)) kg/wk")
        }
        if let emphasis = payload.emphasis {
            parts.append("Emphasis: \(emphasis)")
        }
        let detail = parts.joined(separator: " · ")
        return (
            title: "Update training plan",
            detail: detail.isEmpty ? "No changes" : detail,
            reason: payload.rationale ?? payload.reply
        )
    }
}
