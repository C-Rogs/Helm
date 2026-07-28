import Foundation

public struct NutritionDayLogStatus: Sendable, Hashable, Codable, Equatable {
    public let helmDay: HelmDay
    public let loggingComplete: Bool
    public let markedAt: Date

    public init(helmDay: HelmDay, loggingComplete: Bool, markedAt: Date) {
        self.helmDay = helmDay
        self.loggingComplete = loggingComplete
        self.markedAt = markedAt
    }
}
