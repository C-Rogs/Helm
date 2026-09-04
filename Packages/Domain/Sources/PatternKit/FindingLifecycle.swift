import Foundation

public enum FindingLifecycle {
    public static func status(
        nExp: Int,
        nCtrl: Int,
        cliffsDelta: Double?,
        ciLow: Double?,
        ciHigh: Double?,
        permutationP: Double?,
        fdrQ: Double?,
        verdict: ContrastVerdict,
        hasPrior: Bool,
        previous: FindingStatus?,
        eValue: Double? = nil,
        anytimeStable: Bool = false
    ) -> FindingStatus {
        if previous == .memoryConfirmed {
            return .memoryConfirmed
        }
        if verdict == .suppress {
            return previous ?? .retired
        }
        let minArm = min(nExp, nCtrl)
        if minArm < PatternKit.minArmCount {
            if hasPrior {
                return .priorSeed
            }
            return .retired
        }

        if verdict == .killNull || shouldRetire(delta: cliffsDelta, ciLow: ciLow, ciHigh: ciHigh) {
            return .retired
        }

        let gates = significanceGates(
            delta: cliffsDelta,
            permutationP: permutationP,
            fdrQ: fdrQ
        )
        if !gates && !anytimeStable {
            if previous == .stable || previous == .emerging {
                return shouldRetire(delta: cliffsDelta, ciLow: ciLow, ciHigh: ciHigh) ? .retired : previous ?? .emerging
            }
            return .emerging
        }

        if minArm >= PatternKit.stableArmCount || anytimeStable {
            return .stable
        }
        return .emerging
    }

    public static func significanceGates(
        delta: Double?,
        permutationP: Double?,
        fdrQ: Double?
    ) -> Bool {
        guard let delta, abs(delta) >= PatternKit.minAbsDelta else { return false }
        if let permutationP, permutationP > PatternKit.permutationAlpha { return false }
        if let fdrQ, fdrQ > PatternKit.fdrQ { return false }
        return permutationP != nil || fdrQ != nil
    }

    public static func shouldRetire(delta: Double?, ciLow: Double?, ciHigh: Double?) -> Bool {
        if let delta, abs(delta) < PatternKit.retireAbsDelta {
            return true
        }
        if let ciLow, let ciHigh, ciLow <= 0, ciHigh >= 0 {
            return abs(delta ?? 0) < PatternKit.minAbsDelta
        }
        return false
    }
}
