import Foundation

/// On-device N-of-1 contrast engine. Numbers only; no I/O, no LLM.
public enum PatternKit {
    public static let maxLag = 3
    public static let minArmCount = 12
    public static let stableArmCount = 30
    public static let minAbsDelta = 0.15
    public static let retireAbsDelta = 0.10
    public static let permutationCap = 500
    public static let fdrQ = 0.10
    public static let permutationAlpha = 0.05
    public static let typedSearchBudget = 8
    public static let proposeCap = 5
}
