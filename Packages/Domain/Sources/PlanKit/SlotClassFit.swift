import Foundation

/// Exercise-to-slot fit from catalog class + equipment. No named lift bans.
enum SlotClassFit {
    static func isCompoundOverload(_ pattern: MovementPatternKind) -> Bool {
        switch pattern {
        case .horizontalPress, .verticalPress, .verticalPull, .horizontalPull,
             .kneeExtensionCompound, .hipHinge, .unilateralKnee:
            true
        case .lengthenedChest, .lateralRaise, .tricepsIsolation, .elbowFlexion,
             .rearDelt, .latIsolation, .kneeFlexion, .calf, .core:
            false
        }
    }

    static func preferredClasses(for pattern: MovementPatternKind) -> Set<CatalogMovementClass> {
        switch pattern {
        case .horizontalPress: [.horizontalPush]
        case .verticalPress: [.verticalPush]
        case .verticalPull: [.verticalPull]
        case .horizontalPull: [.horizontalPull]
        case .kneeExtensionCompound: [.squat]
        case .hipHinge: [.hinge]
        case .unilateralKnee: [.lunge]
        case .lengthenedChest, .lateralRaise, .tricepsIsolation, .elbowFlexion,
             .rearDelt, .latIsolation, .kneeFlexion, .calf:
            [.isolation]
        case .core:
            [.core, .isolation]
        }
    }

    static func matchesPreferredClass(_ exercise: CatalogExercise, slot: PatternSlot) -> Bool {
        guard let movementClass = exercise.movementClass, movementClass != .other else {
            return false
        }
        return preferredClasses(for: slot.pattern).contains(movementClass)
    }

    static func classScore(_ exercise: CatalogExercise, slot: PatternSlot) -> Double {
        guard let movementClass = exercise.movementClass, movementClass != .other else {
            return 0
        }
        if preferredClasses(for: slot.pattern).contains(movementClass) {
            return 0.55
        }
        if isCompoundOverload(slot.pattern), movementClass == .isolation {
            return -1.2
        }
        return 0
    }

    static func loadabilityScore(_ exercise: CatalogExercise, slot: PatternSlot) -> Double {
        guard isCompoundOverload(slot.pattern) else { return 0 }
        let loadable = isProgressivelyLoadable(exercise.equipment)
        if slot.role == .primary {
            return loadable ? 0.85 : -1.1
        }
        return loadable ? 0.45 : -0.55
    }

    static func isProgressivelyLoadable(_ equipment: String?) -> Bool {
        guard let equipment else { return false }
        switch equipment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "bodyweight", "body only", "band", "bands":
            return false
        case "barbell", "dumbbell", "machine", "cable", "smith", "kettlebell", "e-z curl bar":
            return true
        default:
            return true
        }
    }
}
