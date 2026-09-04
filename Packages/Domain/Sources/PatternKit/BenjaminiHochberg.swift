import Foundation

public enum BenjaminiHochberg {
    /// Step-up BH q-values aligned to the input order. Nil p-values stay nil.
    public static func qValues(_ pValues: [Double?], q: Double = PatternKit.fdrQ) -> [Double?] {
        _ = q
        let indexed = pValues.enumerated().compactMap { index, p -> (Int, Double)? in
            guard let p else { return nil }
            return (index, p)
        }
        guard !indexed.isEmpty else { return pValues.map { _ in nil } }

        let sorted = indexed.sorted { $0.1 < $1.1 }
        let m = Double(sorted.count)
        var qByInput = Array(repeating: Optional<Double>.none, count: pValues.count)
        var running = 1.0
        for rankRev in stride(from: sorted.count - 1, through: 0, by: -1) {
            let (inputIndex, p) = sorted[rankRev]
            let rank = Double(rankRev + 1)
            let candidate = min(1, p * m / rank)
            running = min(running, candidate)
            qByInput[inputIndex] = running
        }
        return qByInput
    }
}
