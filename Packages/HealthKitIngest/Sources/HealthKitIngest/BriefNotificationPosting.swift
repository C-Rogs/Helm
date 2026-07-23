import Core
import Foundation

public protocol BriefNotificationPosting: Sendable {
    func postMorningBrief(_ brief: StoredDailyBrief) async -> Bool
}

public struct NoOpBriefNotificationPoster: BriefNotificationPosting {
    public init() {}

    public func postMorningBrief(_ brief: StoredDailyBrief) async -> Bool {
        false
    }
}
