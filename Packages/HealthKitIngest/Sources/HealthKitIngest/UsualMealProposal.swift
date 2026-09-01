import Core
import Foundation

/// One-tap usual meal for an empty bucket: saved template or last matching weekday/weekend copy.
public struct UsualMealProposal: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable {
        case template(MealTemplate)
        case copy(from: HelmDay)
    }

    public var id: MealBucket { bucket }

    public let bucket: MealBucket
    public let displayName: String
    public let energyKcal: Int
    public let source: Source

    public init(
        bucket: MealBucket,
        displayName: String,
        energyKcal: Int,
        source: Source
    ) {
        self.bucket = bucket
        self.displayName = displayName
        self.energyKcal = energyKcal
        self.source = source
    }

    public var prompt: String {
        "Usual \(displayName)?"
    }
}

public enum UsualMealLogError: Error, Sendable, Equatable {
    case alreadyLogged
    case noUsual
}

public enum UsualMealLogOutcome: Sendable, Equatable {
    case logged(displayName: String, bucket: MealBucket, helmDay: HelmDay)
    case alreadyLogged(MealBucket)
    case noUsual(MealBucket)
    case failed(String)
}
