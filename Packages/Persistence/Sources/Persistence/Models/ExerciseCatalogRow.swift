import Foundation

/// Raw exercise row used to build PlanKit catalog entries.
public struct ExerciseCatalogRow: Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let primaryMuscleGroup: String?
    public let secondaryMuscleGroups: [String]
    public let equipment: String?
    public let isPickerDefault: Bool
    public let movementPattern: String?
    public let evidence: ExerciseSeedEvidence?

    public init(
        id: String,
        displayName: String,
        primaryMuscleGroup: String?,
        secondaryMuscleGroups: [String],
        equipment: String?,
        isPickerDefault: Bool,
        movementPattern: String? = nil,
        evidence: ExerciseSeedEvidence? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.equipment = equipment
        self.isPickerDefault = isPickerDefault
        self.movementPattern = movementPattern
        self.evidence = evidence
    }
}
