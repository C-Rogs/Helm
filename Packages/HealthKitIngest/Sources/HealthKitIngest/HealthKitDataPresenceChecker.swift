import Foundation
import HealthKit

public struct HealthKitDataPresence: Sendable, Equatable {
    public let kind: HealthKitSampleKind
    public let hasData: Bool

    public init(kind: HealthKitSampleKind, hasData: Bool) {
        self.kind = kind
        self.hasData = hasData
    }
}

/// Verifies whether HealthKit actually contains samples per type.
/// Read denials are invisible by design, so presence of data is the reliable signal.
public struct HealthKitDataPresenceChecker: Sendable {
    private let store: any HealthKitStoreClient

    public init(store: any HealthKitStoreClient = LiveHealthKitStore()) {
        self.store = store
    }

    public func checkAllKinds() async -> [HealthKitDataPresence] {
        guard store.isHealthDataAvailable() else {
            return HealthKitSampleKind.allCases.map { HealthKitDataPresence(kind: $0, hasData: false) }
        }

        var results: [HealthKitDataPresence] = []
        results.reserveCapacity(HealthKitSampleKind.allCases.count)

        for kind in HealthKitSampleKind.allCases {
            let hasData = await hasSamples(for: kind)
            results.append(HealthKitDataPresence(kind: kind, hasData: hasData))
        }
        return results
    }

    public func hasSamples(for kind: HealthKitSampleKind) async -> Bool {
        guard store.isHealthDataAvailable() else { return false }
        do {
            let samples = try await store.fetchSamples(
                sampleType: kind.sampleType,
                predicate: nil,
                limit: 1
            )
            return !samples.isEmpty
        } catch {
            return false
        }
    }
}

public extension HealthKitSampleKind {
    var displayName: String {
        switch self {
        case .hrvSDNN: "Heart rate variability"
        case .restingHeartRate: "Resting heart rate"
        case .sleep: "Sleep"
        case .respiratoryRate: "Respiratory rate"
        case .wristTemperature: "Wrist temperature"
        case .activeEnergy: "Active energy"
        case .dietaryEnergy: "Dietary energy"
        case .dietaryProtein: "Protein"
        case .dietaryCarbohydrate: "Carbohydrates"
        case .dietaryFat: "Fat"
        case .bodyMass: "Body mass"
        case .workout: "Workouts"
        }
    }
}
