import Foundation

public protocol PhotoCofidGroundingPreferences: Sendable {
    func isPhotoCofidGroundingEnabled() -> Bool
}

public struct DefaultPhotoCofidGroundingPreferences: PhotoCofidGroundingPreferences, Sendable {
    public init() {}

    public func isPhotoCofidGroundingEnabled() -> Bool {
        false
    }
}
