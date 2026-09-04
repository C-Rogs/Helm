import Core
import Foundation

/// Rolling 90-day IQR-normalized distance with missing-feature masking.
public enum AnalogousDayEngine {
    public static let windowDays = 90
    public static let nearThreshold = 0.35

    public struct Neighbor: Sendable, Equatable {
        public var helmDay: HelmDay
        public var distance: Double
    }

    public static func neighbors(
        of target: DayFeatureRow,
        in rows: [DayFeatureRow],
        k: Int = 5,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [Neighbor] {
        let windowStart = target.helmDay.adding(days: -(windowDays - 1), calendar: calendar)
        let pool = rows.filter { $0.helmDay >= windowStart && $0.helmDay <= target.helmDay }
        let scales = iqrScales(pool)
        let targetZ = zVector(target, scales: scales)
        var scored: [Neighbor] = []
        for row in pool where row.helmDay != target.helmDay {
            let other = zVector(row, scales: scales)
            let distance = maskedDistance(targetZ, other)
            guard let distance else { continue }
            scored.append(Neighbor(helmDay: row.helmDay, distance: distance))
        }
        return scored.sorted { $0.distance < $1.distance }.prefix(k).map { $0 }
    }

    static func iqrScales(_ rows: [DayFeatureRow]) -> [DayFeatureField: Double] {
        var scales: [DayFeatureField: Double] = [:]
        for field in analogFields {
            let values = rows.compactMap { $0.continuous(field) }.sorted()
            guard values.count >= 4 else { continue }
            let q1 = percentile(values, 0.25)
            let q3 = percentile(values, 0.75)
            let iqr = max(q3 - q1, 1e-6)
            scales[field] = iqr
        }
        return scales
    }

    private static let analogFields: [DayFeatureField] = [
        .dietEnergyKcal, .dietProteinG, .sleepAsleepMin, .hrvSdnn, .restingHr, .workoutMinutes
    ]

    private static let weights: [DayFeatureField: Double] = [
        .dietEnergyKcal: 1,
        .dietProteinG: 1,
        .sleepAsleepMin: 1.2,
        .hrvSdnn: 1.2,
        .restingHr: 1,
        .workoutMinutes: 0.8
    ]

    private static func zVector(
        _ row: DayFeatureRow,
        scales: [DayFeatureField: Double]
    ) -> [DayFeatureField: Double] {
        var z: [DayFeatureField: Double] = [:]
        for field in analogFields {
            guard let value = row.continuous(field), let iqr = scales[field] else { continue }
            z[field] = value / iqr
        }
        return z
    }

    private static func maskedDistance(
        _ a: [DayFeatureField: Double],
        _ b: [DayFeatureField: Double]
    ) -> Double? {
        var sum = 0.0
        var used = 0.0
        for field in analogFields {
            guard let za = a[field], let zb = b[field] else { continue }
            let w = weights[field] ?? 1
            let d = za - zb
            sum += w * d * d
            used += w
        }
        guard used > 0 else { return nil }
        return sqrt(sum / used)
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let idx = p * Double(sorted.count - 1)
        let lo = Int(idx.rounded(.down))
        let hi = Int(idx.rounded(.up))
        if lo == hi { return sorted[lo] }
        let t = idx - Double(lo)
        return sorted[lo] * (1 - t) + sorted[hi] * t
    }
}
