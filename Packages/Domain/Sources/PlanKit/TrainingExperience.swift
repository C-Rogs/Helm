/// Training history used to seed volume landmarks before logged tolerance refines them.
public enum TrainingExperience: String, Sendable, Hashable, Codable, CaseIterable {
    case novice
    case intermediate
    case advanced
}
