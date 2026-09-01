import Foundation

/// User-selectable workout types for the Watch session picker.
public enum WatchWorkoutActivityKind: String, CaseIterable, Sendable, Identifiable {
    case traditionalStrengthTraining
    case functionalStrengthTraining
    case running
    case cycling
    case walking
    case highIntensityIntervalTraining
    case mixedCardio
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .traditionalStrengthTraining: "Strength"
        case .functionalStrengthTraining: "Functional"
        case .running: "Run"
        case .cycling: "Cycle"
        case .walking: "Walk"
        case .highIntensityIntervalTraining: "HIIT"
        case .mixedCardio: "Cardio"
        case .other: "Other"
        }
    }

    public var usesOutdoorLocation: Bool {
        switch self {
        case .running, .cycling, .walking: true
        default: false
        }
    }

    /// Raw HealthKit activity type identifier (mirrors `HKWorkoutActivityType` raw values).
    public var healthKitActivityTypeRawValue: UInt {
        switch self {
        case .traditionalStrengthTraining: 50
        case .functionalStrengthTraining: 20
        case .running: 37
        case .cycling: 13
        case .walking: 52
        case .highIntensityIntervalTraining: 63
        case .mixedCardio: 73
        case .other: 3000
        }
    }

    public static func fromHealthKitActivityTypeRawValue(_ rawValue: UInt) -> WatchWorkoutActivityKind {
        Self.allCases.first { $0.healthKitActivityTypeRawValue == rawValue } ?? .traditionalStrengthTraining
    }

    /// Infer HK activity from a Helm session title + exercise names/modes.
    /// Mixed lift + cardio stays strength. Cardio-only sessions map run/cycle/walk/HIIT.
    public static func inferred(
        sessionTitle: String?,
        exerciseNames: [String],
        exerciseModes: [ExerciseMode] = []
    ) -> WatchWorkoutActivityKind {
        let joined = ([sessionTitle].compactMap { $0 } + exerciseNames)
            .map { $0.lowercased() }
            .joined(separator: " ")

        let cardioModeCount = exerciseModes.filter { $0 == .duration || $0 == .distanceDuration }.count
        let strengthModeCount = exerciseModes.filter { $0 == .weightReps || $0 == .bodyweightReps }.count
        let allCardio = !exerciseModes.isEmpty && cardioModeCount == exerciseModes.count

        if strengthModeCount > 0 && !allCardio {
            return .traditionalStrengthTraining
        }

        func containsAny(_ needles: [String]) -> Bool {
            needles.contains { joined.contains($0) }
        }

        let looksCardio = allCardio
            || (strengthModeCount == 0 && (
                containsAny(Self.runNeedles + Self.cycleNeedles + Self.walkNeedles + Self.hiitNeedles + Self.cardioNeedles)
                    || cardioModeCount > strengthModeCount
            ))

        guard looksCardio else {
            return .traditionalStrengthTraining
        }

        if containsAny(Self.runNeedles) { return .running }
        if containsAny(Self.hiitNeedles) { return .highIntensityIntervalTraining }
        if containsAny(Self.cycleNeedles) { return .cycling }
        if containsAny(Self.walkNeedles) { return .walking }
        return .mixedCardio
    }

    private static let runNeedles = ["run", "jog", "treadmill"]
    private static let cycleNeedles = ["cycle", "bike", "ride", "cycling"]
    private static let walkNeedles = ["walk", "hike"]
    private static let hiitNeedles = ["hiit", "interval"]
    private static let cardioNeedles = ["cardio", "row", "swim", "elliptical"]
}
