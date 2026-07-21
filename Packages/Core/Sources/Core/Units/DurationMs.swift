/// Durations where unit confusion is costly (HRV SDNN, latency).
public struct DurationMs: Sendable, Hashable, Codable {
    public let milliseconds: Int

    public init(milliseconds: Int) {
        self.milliseconds = milliseconds
    }

    public var seconds: Double {
        Double(milliseconds) / 1_000
    }
}
