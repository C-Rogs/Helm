/// Local time-of-day when one logical Helm day ends and the next begins.
public struct DayCutoff: Sendable, Hashable, Codable {
    public let hour: Int
    public let minute: Int

    /// Default end-of-day boundary: 04:00 local.
    public static let `default` = DayCutoff(hour: 4, minute: 0)

    public init(hour: Int, minute: Int) {
        precondition((0 ..< 24).contains(hour), "hour must be 0...23")
        precondition((0 ..< 60).contains(minute), "minute must be 0...59")
        self.hour = hour
        self.minute = minute
    }
}
