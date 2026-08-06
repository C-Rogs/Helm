import Core
import Foundation

public struct LoadIncrement: Sendable, Hashable, Codable {
    public let stepKilograms: Double

    public init(stepKilograms: Double) {
        self.stepKilograms = stepKilograms
    }

    /// Smallest usable pair of plates on a barbell.
    public static let barbell = LoadIncrement(stepKilograms: 2.5)
    /// Dumbbells come in pairs; 1 kg per hand.
    public static let dumbbell = LoadIncrement(stepKilograms: 2.0)
    /// Typical machine stack pin increment.
    public static let machine = LoadIncrement(stepKilograms: 5.0)
    public static let cable = LoadIncrement(stepKilograms: 2.5)
    public static let microplate = LoadIncrement(stepKilograms: 0.5)
    /// Zero step means do not round.
    public static let bodyweight = LoadIncrement(stepKilograms: 0.0)
}

public enum LoadRounding {
    /// Snap to the nearest loadable weight.
    public static func snap(_ proposed: Mass, to increment: LoadIncrement) -> Mass {
        let sanitizedKg = sanitizedKilograms(proposed.kilograms)
        let step = increment.stepKilograms
        guard step > 0 else {
            return Mass(kilograms: sanitizedKg)
        }
        let snapped = (sanitizedKg / step).rounded() * step
        return Mass(kilograms: max(0, snapped))
    }

    /// Snap a progression, guaranteeing it actually moves when the intent was to move.
    public static func snapProgression(
        from current: Mass,
        proposed: Mass,
        increment: LoadIncrement
    ) -> Mass {
        let currentKg = sanitizedKilograms(current.kilograms)
        let proposedKg = sanitizedKilograms(proposed.kilograms)

        if proposedKg == currentKg {
            return Mass(kilograms: currentKg)
        }

        let step = increment.stepKilograms
        guard step > 0 else {
            return Mass(kilograms: proposedKg)
        }

        let snapped = snap(Mass(kilograms: proposedKg), to: increment)
        let snappedKg = snapped.kilograms

        if proposedKg > currentKg, snappedKg <= currentKg {
            return Mass(kilograms: currentKg + step)
        }
        if proposedKg < currentKg, snappedKg >= currentKg {
            return Mass(kilograms: max(0, currentKg - step))
        }
        return snapped
    }

    private static func sanitizedKilograms(_ kilograms: Double) -> Double {
        guard kilograms.isFinite else { return 0 }
        return max(0, kilograms)
    }
}
