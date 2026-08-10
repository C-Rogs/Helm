import Foundation

/// A knowledge domain the coach can load (hypertrophy, nutrition, recovery, etc.).
public struct ResourceModule: Sendable, Hashable, Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let topicIDs: [String]
    public let evidenceIDs: [String]
    public let autoAssign: ResourceModuleAutoAssign?

    public init(
        id: String,
        title: String,
        description: String,
        topicIDs: [String] = [],
        evidenceIDs: [String] = [],
        autoAssign: ResourceModuleAutoAssign? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.topicIDs = topicIDs
        self.evidenceIDs = evidenceIDs
        self.autoAssign = autoAssign
    }
}

/// Rules for automatically activating a module based on athlete profile.
public struct ResourceModuleAutoAssign: Sendable, Hashable, Codable, Equatable {
    public let phases: [TrainingPhase]?
    public let goals: [String]?
    public let always: Bool

    public init(
        phases: [TrainingPhase]? = nil,
        goals: [String]? = nil,
        always: Bool = false
    ) {
        self.phases = phases
        self.goals = goals
        self.always = always
    }
}
