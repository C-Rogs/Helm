import Foundation

/// Scores catalog exercises against a movement-pattern slot using id heuristics + primary muscle.
enum MovementPatternMatcher {
    static func matches(_ exercise: CatalogExercise, slot: PatternSlot) -> Bool {
        guard primaryMuscle(of: exercise) == slot.primaryMuscle
            || exercise.muscleMap.contributions.contains(where: { $0.muscle == slot.primaryMuscle && $0.fraction >= 0.25 })
        else {
            return false
        }
        return patternScore(exerciseID: exercise.exerciseID, pattern: slot.pattern) > 0
            || softMuscleFallback(exercise: exercise, slot: slot)
    }

    static func patternScore(exerciseID: String, pattern: MovementPatternKind) -> Double {
        let id = exerciseID.lowercased()
        let needles = keywords(for: pattern)
        guard !needles.isEmpty else { return 0 }
        var score = 0.0
        for needle in needles where id.contains(needle) {
            score += 1.0
        }
        return score
    }

    /// When no keyword hits, still allow a primary-muscle match for required slots.
    static func softMuscleFallback(exercise: CatalogExercise, slot: PatternSlot) -> Bool {
        primaryMuscle(of: exercise) == slot.primaryMuscle
    }

    static func primaryMuscle(of exercise: CatalogExercise) -> MuscleGroup? {
        exercise.muscleMap.contributions.max(by: { $0.fraction < $1.fraction })?.muscle
    }

    private static func keywords(for pattern: MovementPatternKind) -> [String] {
        switch pattern {
        case .horizontalPress:
            ["bench", "chest_press", "push_up", "pushup", "floor_press", "dip"]
        case .verticalPress:
            ["overhead", "shoulder_press", "military", "ohp", "landmine_press"]
        case .lengthenedChest:
            ["fly", "pec_deck", "cable_crossover", "crossover", "incline_fly"]
        case .lateralRaise:
            ["lateral_raise", "side_raise", "lateral_delt"]
        case .tricepsIsolation:
            ["triceps", "pushdown", "skull", "extension", "kickback", "close_grip"]
        case .verticalPull:
            ["pulldown", "pull_up", "pullup", "chin_up", "chinup", "lat_pull"]
        case .horizontalPull:
            ["row", "seal_row", "chest_supported", "pendlay", "meadow"]
        case .latIsolation:
            ["straight_arm", "pullover", "lat_prayer"]
        case .elbowFlexion:
            ["curl", "preacher", "hammer", "bayesian", "concentration"]
        case .rearDelt:
            ["rear_delt", "face_pull", "reverse_fly", "reverse_pec", "band_pull_apart"]
        case .kneeExtensionCompound:
            ["squat", "leg_press", "hack", "belt_squat", "pendulum"]
        case .hipHinge:
            ["rdl", "deadlift", "hip_thrust", "good_morning", "back_extension", "hinge"]
        case .unilateralKnee:
            ["lunge", "split_squat", "step_up", "bulgarian", "pistol"]
        case .kneeFlexion:
            ["leg_curl", "nordic", "hamstring_curl"]
        case .calf:
            ["calf", "gastroc", "soleus"]
        case .core:
            ["crunch", "plank", "leg_raise", "ab_wheel", "cable_crunch", "hollow"]
        }
    }
}
