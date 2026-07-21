/// Logged tolerance signals used to refine per-muscle volume landmarks between blocks.
public struct ToleranceSignals: Sendable, Hashable, Codable {
    /// Mean reps in reserve across working sets this week (lower = harder).
    public let averageRIR: Double?
    /// Subjective soreness 0 (none) to 10 (severe).
    public let sorenessRating: Int?
    /// Recent performance trend for the muscle's primary lifts.
    public let performanceTrend: PerformanceTrend

    public init(
        averageRIR: Double? = nil,
        sorenessRating: Int? = nil,
        performanceTrend: PerformanceTrend = .stagnant
    ) {
        if let sorenessRating {
            precondition((0 ... 10).contains(sorenessRating), "soreness must be 0...10")
        }
        self.averageRIR = averageRIR
        self.sorenessRating = sorenessRating
        self.performanceTrend = performanceTrend
    }
}

public enum PerformanceTrend: String, Sendable, Hashable, Codable {
    case improving
    case stagnant
    case declining
}
