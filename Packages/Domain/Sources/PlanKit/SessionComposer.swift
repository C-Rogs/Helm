import Foundation
import ReadinessKit

/// Movement vector a composer slot must fill.
public enum MovementPatternKind: String, Sendable, Hashable, Codable, CaseIterable {
    case horizontalPress
    case verticalPress
    case lengthenedChest
    case lateralRaise
    case tricepsIsolation
    case verticalPull
    case horizontalPull
    case latIsolation
    case elbowFlexion
    case rearDelt
    case kneeExtensionCompound
    case hipHinge
    case unilateralKnee
    case kneeFlexion
    case calf
    case core
}

public enum PatternSlotRole: String, Sendable, Hashable, Codable {
    case primary
    case secondary
    case isolation
}

/// One required (or optional) exercise slot in a composed session.
public struct PatternSlot: Sendable, Hashable, Codable, Identifiable {
    public var id: String { "\(index)-\(pattern.rawValue)-\(primaryMuscle.rawValue)-\(role.rawValue)" }

    public let index: Int
    public let pattern: MovementPatternKind
    public let primaryMuscle: MuscleGroup
    public let role: PatternSlotRole
    /// When false, composer may skip if catalog/time cannot fill it.
    public let required: Bool

    public init(
        index: Int = 0,
        pattern: MovementPatternKind,
        primaryMuscle: MuscleGroup,
        role: PatternSlotRole,
        required: Bool = true
    ) {
        self.index = index
        self.pattern = pattern
        self.primaryMuscle = primaryMuscle
        self.role = role
        self.required = required
    }
}

/// Builds the ordered pattern-slot list for a training day.
public enum SessionComposer {
    /// Whether a thin (≤2 exercise) session is an allowed exception.
    public static func allowsThinSession(
        budget: SessionDurationBudget,
        readinessBand: ReadinessBand?,
        isDeload: Bool
    ) -> Bool {
        if isDeload { return true }
        if budget == .minutes30 { return true }
        if readinessBand == .depleted { return true }
        return false
    }

    public static func slots(
        dayKind: TrainingDayKind,
        budget: SessionDurationBudget,
        template: ProgramTemplate = .ppl,
        readinessBand: ReadinessBand? = nil,
        isDeload: Bool = false
    ) -> [PatternSlot] {
        // Non-PPL templates fall back to PPL day kinds until dedicated tables ship.
        _ = template
        let thin = allowsThinSession(budget: budget, readinessBand: readinessBand, isDeload: isDeload)
        let catalog = indexed(baseSlots(for: dayKind))
        let capped = Array(catalog.prefix(budget.maxSlots))
        if thin || isDeload {
            let keep = max(2, min(capped.count, budget == .minutes30 ? 2 : budget.maxSlots - 2))
            return Array(capped.prefix(keep))
        }
        return capped
    }

    private static func indexed(_ slots: [PatternSlot]) -> [PatternSlot] {
        slots.enumerated().map { offset, slot in
            PatternSlot(
                index: offset,
                pattern: slot.pattern,
                primaryMuscle: slot.primaryMuscle,
                role: slot.role,
                required: slot.required
            )
        }
    }

    public static func primaryMuscles(in slots: [PatternSlot]) -> [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        var ordered: [MuscleGroup] = []
        for slot in slots {
            if seen.insert(slot.primaryMuscle).inserted {
                ordered.append(slot.primaryMuscle)
            }
        }
        return ordered
    }

    private static func baseSlots(for dayKind: TrainingDayKind) -> [PatternSlot] {
        switch dayKind {
        case .push:
            [
                PatternSlot(pattern: .horizontalPress, primaryMuscle: .chest, role: .primary),
                PatternSlot(pattern: .verticalPress, primaryMuscle: .shoulders, role: .primary),
                PatternSlot(pattern: .lengthenedChest, primaryMuscle: .chest, role: .secondary),
                PatternSlot(pattern: .lateralRaise, primaryMuscle: .shoulders, role: .isolation),
                PatternSlot(pattern: .tricepsIsolation, primaryMuscle: .triceps, role: .isolation),
                PatternSlot(pattern: .tricepsIsolation, primaryMuscle: .triceps, role: .isolation, required: false)
            ]
        case .pull:
            [
                PatternSlot(pattern: .verticalPull, primaryMuscle: .back, role: .primary),
                PatternSlot(pattern: .horizontalPull, primaryMuscle: .back, role: .primary),
                PatternSlot(pattern: .latIsolation, primaryMuscle: .back, role: .secondary, required: false),
                PatternSlot(pattern: .elbowFlexion, primaryMuscle: .biceps, role: .isolation),
                PatternSlot(pattern: .rearDelt, primaryMuscle: .shoulders, role: .isolation),
                PatternSlot(pattern: .elbowFlexion, primaryMuscle: .biceps, role: .isolation, required: false)
            ]
        case .legs:
            [
                PatternSlot(pattern: .kneeExtensionCompound, primaryMuscle: .quads, role: .primary),
                PatternSlot(pattern: .hipHinge, primaryMuscle: .hamstrings, role: .primary),
                PatternSlot(pattern: .unilateralKnee, primaryMuscle: .quads, role: .secondary),
                PatternSlot(pattern: .kneeFlexion, primaryMuscle: .hamstrings, role: .isolation),
                PatternSlot(pattern: .hipHinge, primaryMuscle: .glutes, role: .secondary, required: false),
                PatternSlot(pattern: .calf, primaryMuscle: .calves, role: .isolation),
                PatternSlot(pattern: .core, primaryMuscle: .abs, role: .isolation, required: false)
            ]
        case .upper:
            // Temporary: push-like until Upper/Lower tables ship.
            baseSlots(for: .push)
        case .lower:
            baseSlots(for: .legs)
        case .full:
            [
                PatternSlot(pattern: .kneeExtensionCompound, primaryMuscle: .quads, role: .primary),
                PatternSlot(pattern: .horizontalPress, primaryMuscle: .chest, role: .primary),
                PatternSlot(pattern: .horizontalPull, primaryMuscle: .back, role: .primary),
                PatternSlot(pattern: .hipHinge, primaryMuscle: .hamstrings, role: .secondary),
                PatternSlot(pattern: .verticalPress, primaryMuscle: .shoulders, role: .isolation),
                PatternSlot(pattern: .elbowFlexion, primaryMuscle: .biceps, role: .isolation, required: false)
            ]
        }
    }
}
