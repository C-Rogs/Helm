import Core
import Foundation

enum EpleyOneRepMax {
    static func estimate(mass: Mass, reps: Int) -> Mass {
        let kilograms = mass.kilograms * (1.0 + Double(reps) / 30.0)
        return Mass(kilograms: kilograms)
    }
}
