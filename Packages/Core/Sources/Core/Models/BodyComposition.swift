import Foundation

public struct BodyComposition: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let helmDay: HelmDay
    public let mass: Mass
    public let bodyFatPercentage: Double?
    public let measuredAt: Date

    public init(
        id: UUID = UUID(),
        helmDay: HelmDay,
        mass: Mass,
        bodyFatPercentage: Double? = nil,
        measuredAt: Date
    ) {
        self.id = id
        self.helmDay = helmDay
        self.mass = mass
        self.bodyFatPercentage = bodyFatPercentage
        self.measuredAt = measuredAt
    }
}
