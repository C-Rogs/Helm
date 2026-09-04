import Foundation

/// Anytime-valid e-value for a two-sample mean difference under a Gaussian betting model.
public enum MeanDifferenceEProcess {
    public static func eValue(exposure: [Double], control: [Double]) -> Double? {
        guard exposure.count >= 2, control.count >= 2 else { return nil }
        let meanExp = exposure.reduce(0, +) / Double(exposure.count)
        let meanCtrl = control.reduce(0, +) / Double(control.count)
        let diff = meanExp - meanCtrl
        let se = pooledSE(exposure, control)
        guard se > 0 else { return abs(diff) > 0 ? 20 : 1 }
        let z = diff / se
        let e = exp(-0.5) * exp(0.5 * z * z)
        return min(max(e, 0), 1e9)
    }

    /// LIL-style radius so CS coverage can be checked under optional stopping.
    public static func confidenceRadius(n: Int, sigma: Double, alpha: Double = PatternKit.permutationAlpha) -> Double {
        let nn = max(n, 3)
        let loglog = log(log(Double(nn)))
        return sigma * sqrt((2 * max(loglog, 0.1) + log(1 / alpha)) / Double(nn))
    }

    public static func excludesZero(mean: Double, n: Int, sigma: Double, alpha: Double = PatternKit.permutationAlpha) -> Bool {
        abs(mean) > confidenceRadius(n: n, sigma: sigma, alpha: alpha)
    }

    private static func pooledSE(_ a: [Double], _ b: [Double]) -> Double {
        func variance(_ xs: [Double]) -> Double {
            let mean = xs.reduce(0, +) / Double(xs.count)
            let ss = xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            return ss / Double(xs.count - 1)
        }
        let va = variance(a)
        let vb = variance(b)
        return sqrt(va / Double(a.count) + vb / Double(b.count))
    }
}
