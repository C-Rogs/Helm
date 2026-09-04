import Accelerate
import Foundation

public struct CliffsDeltaEstimate: Sendable, Equatable {
    public var delta: Double
    public var variance: Double
    public var standardError: Double
    public var ciLow: Double
    public var ciHigh: Double

    public init(delta: Double, variance: Double, standardError: Double, ciLow: Double, ciHigh: Double) {
        self.delta = delta
        self.variance = variance
        self.standardError = standardError
        self.ciLow = ciLow
        self.ciHigh = ciHigh
    }
}

public enum CliffsDelta {
    public static let zCrit = 1.959963984540054

    public static func estimate(exposure: [Double], control: [Double]) -> CliffsDeltaEstimate? {
        let n1 = exposure.count
        let n2 = control.count
        guard n1 > 0, n2 > 0 else { return nil }

        var dominance = [Double](repeating: 0, count: n1 * n2)
        var negatedControl = [Double](repeating: 0, count: n2)
        vDSP_vnegD(control, 1, &negatedControl, 1, vDSP_Length(n2))

        for i in 0 ..< n1 {
            var row = [Double](repeating: 0, count: n2)
            let xi = [Double](repeating: exposure[i], count: n2)
            vDSP_vaddD(xi, 1, negatedControl, 1, &row, 1, vDSP_Length(n2))
            for j in 0 ..< n2 {
                if row[j] > 0 {
                    row[j] = 1
                } else if row[j] < 0 {
                    row[j] = -1
                } else {
                    row[j] = 0
                }
            }
            dominance.replaceSubrange((i * n2) ..< ((i + 1) * n2), with: row)
        }

        var delta = 0.0
        vDSP_meanvD(dominance, 1, &delta, vDSP_Length(n1 * n2))

        var rowMeans = [Double](repeating: 0, count: n1)
        for i in 0 ..< n1 {
            var mean = 0.0
            dominance.withUnsafeBufferPointer { buffer in
                vDSP_meanvD(buffer.baseAddress! + i * n2, 1, &mean, vDSP_Length(n2))
            }
            rowMeans[i] = mean
        }

        var colMeans = [Double](repeating: 0, count: n2)
        for j in 0 ..< n2 {
            var sum = 0.0
            for i in 0 ..< n1 {
                sum += dominance[i * n2 + j]
            }
            colMeans[j] = sum / Double(n1)
        }

        let sRow = sampleVariance(rowMeans)
        let sCol = sampleVariance(colMeans)
        let sAll = sampleVariance(dominance)
        let denom = pow(Double(n1 * n2), 2)
        let variance = (
            pow(Double(n2), 2) * sRow + pow(Double(n1), 2) * sCol + sAll
        ) / denom
        let se = sqrt(max(variance, 0))
        let (ciLow, ciHigh) = rangePreservingCI(delta: delta, se: se)
        return CliffsDeltaEstimate(
            delta: delta,
            variance: variance,
            standardError: se,
            ciLow: ciLow,
            ciHigh: ciHigh
        )
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func rangePreservingCI(delta: Double, se: Double, z: Double = zCrit) -> (Double, Double) {
        let zse = z * se
        let lowDen = 1 - delta * zse
        let highDen = 1 + delta * zse
        let low = lowDen == 0 ? -1 : (delta - zse) / lowDen
        let high = highDen == 0 ? 1 : (delta + zse) / highDen
        return (min(max(low, -1), 1), min(max(high, -1), 1))
    }

    private static func sampleVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        var mean = 0.0
        vDSP_meanvD(values, 1, &mean, vDSP_Length(values.count))
        var centered = [Double](repeating: 0, count: values.count)
        var negMean = -mean
        vDSP_vsaddD(values, 1, &negMean, &centered, 1, vDSP_Length(values.count))
        var sumSquares = 0.0
        vDSP_svesqD(centered, 1, &sumSquares, vDSP_Length(values.count))
        return sumSquares / Double(values.count - 1)
    }
}
