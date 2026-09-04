import Foundation

/// LORD++ α-investing for sequential tests. Same AST is not re-spent on nightly retests.
public struct LORDPlusPlusState: Sendable, Hashable, Codable, Equatable {
    public var wealth0: Double
    public var alphaEarn: Double
    public var testIndex: Int
    public var rejectionTimes: [Int]
    public var spentIDs: [String]

    public init(
        wealth0: Double = 0.05,
        alphaEarn: Double = 0.05,
        testIndex: Int = 0,
        rejectionTimes: [Int] = [],
        spentIDs: [String] = []
    ) {
        self.wealth0 = wealth0
        self.alphaEarn = alphaEarn
        self.testIndex = testIndex
        self.rejectionTimes = rejectionTimes
        self.spentIDs = spentIDs
    }

    public mutating func spend(p: Double, id: String? = nil) -> (alpha: Double, rejected: Bool) {
        if let id, spentIDs.contains(id) {
            return (0, p <= PatternKit.permutationAlpha)
        }
        testIndex += 1
        let t = testIndex
        var alpha = Self.gamma(t) * wealth0
        for tau in rejectionTimes where tau < t {
            alpha += Self.gamma(t - tau) * alphaEarn
        }
        alpha = min(alpha, wealth0)
        let rejected = p <= alpha
        if rejected {
            rejectionTimes.append(t)
        }
        if let id {
            spentIDs.append(id)
        }
        return (alpha, rejected)
    }

    /// γ_t = 6 / (π² t²), sums to 1.
    public static func gamma(_ t: Int) -> Double {
        let tt = max(t, 1)
        return 6 / (.pi * .pi * Double(tt * tt))
    }
}

/// SAFFRON-style candidate threshold using λ to skip likely nulls.
public struct SaffronState: Sendable, Hashable, Codable, Equatable {
    public var lambda: Double
    public var wealth: Double
    public var candidates: Int
    public var rejections: Int

    public init(lambda: Double = 0.5, wealth: Double = 0.05, candidates: Int = 0, rejections: Int = 0) {
        self.lambda = lambda
        self.wealth = wealth
        self.candidates = candidates
        self.rejections = rejections
    }

    public mutating func spend(p: Double) -> (alpha: Double, rejected: Bool) {
        if p > lambda {
            return (0, false)
        }
        candidates += 1
        let alpha = min(wealth * lambda / Double(max(candidates, 1)), wealth)
        let rejected = p <= alpha
        if rejected {
            rejections += 1
            wealth += 0.05 - alpha
        } else {
            wealth = max(0, wealth - alpha)
        }
        return (alpha, rejected)
    }
}
