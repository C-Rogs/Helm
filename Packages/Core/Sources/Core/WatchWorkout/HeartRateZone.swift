import Foundation

/// Edwards-style heart-rate reserve zones (1–5), aligned with `StrainCalculator` TRIMP weights.
public enum HeartRateZone: Int, Sendable, CaseIterable, Comparable {
    case zone1 = 1
    case zone2 = 2
    case zone3 = 3
    case zone4 = 4
    case zone5 = 5

    public var displayName: String { "Z\(rawValue)" }

    public static func < (lhs: HeartRateZone, rhs: HeartRateZone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func zone(
        heartRateBPM: Double,
        restingHR: Double,
        maxHR: Double
    ) -> HeartRateZone? {
        guard maxHR > restingHR, heartRateBPM > 0 else { return nil }
        let hrrPercent = (heartRateBPM - restingHR) / (maxHR - restingHR) * 100
        switch hrrPercent {
        case ..<70: return .zone1
        case ..<80: return .zone2
        case ..<90: return .zone3
        case ..<100: return .zone4
        default: return .zone5
        }
    }
}
