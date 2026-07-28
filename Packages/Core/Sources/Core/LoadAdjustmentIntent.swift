import Foundation

/// Whether a load change came from an explicit athlete instruction or a coach suggestion.
public enum LoadAdjustmentIntent: String, Sendable, Hashable, Codable {
    case userDirected
    case coachSuggested
}
