import Core
import Foundation
import HealthKit

public struct HealthKitBodyProfileReader: Sendable {
    private let storeClient: any HealthKitStoreClient
    private let healthStore: HKHealthStore

    public init(
        storeClient: any HealthKitStoreClient = LiveHealthKitStore(),
        healthStore: HKHealthStore = HKHealthStore()
    ) {
        self.storeClient = storeClient
        self.healthStore = healthStore
    }

    public func fetchPrefill() async -> BodyProfile? {
        guard storeClient.isHealthDataAvailable() else { return nil }

        async let bodyMassKg = latestQuantityKilograms(for: .bodyMass)
        async let heightCm = latestQuantityCentimeters(for: .height)
        let biologicalSex = biologicalSexFromHealthKit()
        let dateOfBirth = dateOfBirthFromHealthKit()

        guard
            let bodyMassKg = await bodyMassKg,
            let heightCm = await heightCm,
            let biologicalSex,
            let dateOfBirth
        else {
            return nil
        }

        let profile = BodyProfile(
            bodyMassKg: bodyMassKg,
            heightCm: heightCm,
            biologicalSex: biologicalSex,
            dateOfBirth: dateOfBirth
        )
        return profile.isComplete ? profile : nil
    }

    public func partialPrefill() async -> PartialBodyProfilePrefill {
        async let bodyMassKg = latestQuantityKilograms(for: .bodyMass)
        async let heightCm = latestQuantityCentimeters(for: .height)
        return PartialBodyProfilePrefill(
            bodyMassKg: await bodyMassKg,
            heightCm: await heightCm,
            biologicalSex: biologicalSexFromHealthKit(),
            dateOfBirth: dateOfBirthFromHealthKit()
        )
    }

    private func latestQuantityKilograms(for identifier: HKQuantityTypeIdentifier) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        let samples = (try? await storeClient.fetchSamples(
            sampleType: quantityType,
            predicate: nil,
            limit: HKObjectQueryNoLimit
        )) ?? []
        guard let latest = samples.compactMap({ $0 as? HKQuantitySample }).max(by: { $0.startDate < $1.startDate }) else {
            return nil
        }
        let kilograms = latest.quantity.doubleValue(for: .gramUnit(with: .kilo))
        return kilograms > 1 ? kilograms : nil
    }

    private func latestQuantityCentimeters(for identifier: HKQuantityTypeIdentifier) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        let samples = (try? await storeClient.fetchSamples(
            sampleType: quantityType,
            predicate: nil,
            limit: HKObjectQueryNoLimit
        )) ?? []
        guard let latest = samples.compactMap({ $0 as? HKQuantitySample }).max(by: { $0.startDate < $1.startDate }) else {
            return nil
        }
        let centimeters = latest.quantity.doubleValue(for: .meterUnit(with: .centi))
        return centimeters > 30 ? centimeters : nil
    }

    private func biologicalSexFromHealthKit() -> BiologicalSex? {
        guard let sexObject = try? healthStore.biologicalSex() else { return nil }
        switch sexObject.biologicalSex {
        case .female:
            return .female
        case .male:
            return .male
        case .other:
            return .other
        case .notSet:
            return nil
        @unknown default:
            return nil
        }
    }

    private func dateOfBirthFromHealthKit() -> Date? {
        guard let components = try? healthStore.dateOfBirthComponents() else {
            return nil
        }
        return Calendar.current.date(from: components)
    }
}

public struct PartialBodyProfilePrefill: Sendable, Equatable {
    public let bodyMassKg: Double?
    public let heightCm: Double?
    public let biologicalSex: BiologicalSex?
    public let dateOfBirth: Date?

    public init(
        bodyMassKg: Double?,
        heightCm: Double?,
        biologicalSex: BiologicalSex?,
        dateOfBirth: Date?
    ) {
        self.bodyMassKg = bodyMassKg
        self.heightCm = heightCm
        self.biologicalSex = biologicalSex
        self.dateOfBirth = dateOfBirth
    }

    public func merged(into profile: BodyProfile) -> BodyProfile {
        BodyProfile(
            bodyMassKg: bodyMassKg ?? profile.bodyMassKg,
            heightCm: heightCm ?? profile.heightCm,
            biologicalSex: biologicalSex ?? profile.biologicalSex,
            dateOfBirth: dateOfBirth ?? profile.dateOfBirth
        )
    }

    public func asBodyProfile(fallbackDateOfBirth: Date) -> BodyProfile? {
        guard
            let bodyMassKg,
            let heightCm,
            let biologicalSex
        else {
            return nil
        }
        let profile = BodyProfile(
            bodyMassKg: bodyMassKg,
            heightCm: heightCm,
            biologicalSex: biologicalSex,
            dateOfBirth: dateOfBirth ?? fallbackDateOfBirth
        )
        return profile.isComplete ? profile : nil
    }
}
