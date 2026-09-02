import Foundation

/// Per-exercise evidence ratings used by the selection model.
public struct ExerciseEvidenceRatings: Sendable, Hashable, Codable {
    public let effectiveness: Double
    public let stretchPositionBias: Double
    public let stimulusToFatigue: Double
    public let citationIDs: [String]

    public init(
        effectiveness: Double,
        stretchPositionBias: Double,
        stimulusToFatigue: Double,
        citationIDs: [String]
    ) {
        precondition((0 ... 1).contains(effectiveness))
        precondition((0 ... 1).contains(stretchPositionBias))
        precondition((0 ... 1).contains(stimulusToFatigue))
        self.effectiveness = effectiveness
        self.stretchPositionBias = stretchPositionBias
        self.stimulusToFatigue = stimulusToFatigue
        self.citationIDs = citationIDs
    }

    public static func clamped(
        effectiveness: Double,
        stretchPositionBias: Double,
        stimulusToFatigue: Double,
        citationIDs: [String]
    ) -> ExerciseEvidenceRatings {
        func unit(_ value: Double) -> Double {
            min(1, max(0, value))
        }
        return ExerciseEvidenceRatings(
            effectiveness: unit(effectiveness),
            stretchPositionBias: unit(stretchPositionBias),
            stimulusToFatigue: unit(stimulusToFatigue),
            citationIDs: citationIDs
        )
    }
}
