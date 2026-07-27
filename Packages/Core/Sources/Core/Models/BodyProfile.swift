import Foundation

public enum BiologicalSex: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case female
    case male
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .other: "Other"
        }
    }
}

/// Canonical body metrics used for nutrition TDEE seeding.
public struct BodyProfile: Sendable, Hashable, Codable, Equatable {
    public var bodyMassKg: Double
    public var heightCm: Double
    public var biologicalSex: BiologicalSex
    public var dateOfBirth: Date

    public init(
        bodyMassKg: Double,
        heightCm: Double,
        biologicalSex: BiologicalSex,
        dateOfBirth: Date
    ) {
        self.bodyMassKg = bodyMassKg
        self.heightCm = heightCm
        self.biologicalSex = biologicalSex
        self.dateOfBirth = dateOfBirth
    }

    public var isComplete: Bool {
        bodyMassKg > 1
            && heightCm > 30
            && heightCm < 300
    }

    public func ageYears(calendar: Calendar = .current, on referenceDate: Date = Date()) -> Int {
        let components = calendar.dateComponents([.year], from: dateOfBirth, to: referenceDate)
        return max(components.year ?? 0, 0)
    }

    public func withUpdatedBodyMassKg(_ bodyMassKg: Double) -> BodyProfile {
        var copy = self
        copy.bodyMassKg = bodyMassKg
        return copy
    }
}
