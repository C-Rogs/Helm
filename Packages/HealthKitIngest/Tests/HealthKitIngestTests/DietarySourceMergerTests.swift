import Core
import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Dietary source merger")
struct DietarySourceMergerTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar(identifier: .gregorian)
    private let day = HelmDay.day(for: Date(timeIntervalSince1970: 1_700_000_000), calendar: Calendar(identifier: .gregorian))

    private func helmMeal(
        kcal: Double,
        offsetMinutes: Int = 0,
        source: MealRecord.Source = .manual
    ) -> MealRecord {
        MealRecord(
            helmDay: day,
            name: "Helm meal",
            loggedAt: loggedAt.addingTimeInterval(TimeInterval(offsetMinutes * 60)),
            bucket: .lunch,
            energy: Energy(kilocalories: kcal),
            proteinGrams: 30,
            carbohydrateGrams: 40,
            fatGrams: 10,
            source: source
        )
    }

    private func externalMeal(kcal: Double, offsetMinutes: Int = 0) -> MealRecord {
        MealRecord(
            helmDay: day,
            name: "HealthKit meal",
            loggedAt: loggedAt.addingTimeInterval(TimeInterval(offsetMinutes * 60)),
            bucket: .lunch,
            energy: Energy(kilocalories: kcal),
            proteinGrams: 30,
            carbohydrateGrams: 40,
            fatGrams: 10,
            source: .healthKit,
            externalSampleID: UUID().uuidString
        )
    }

    @Test("Helm and MFP duplicate within window prefers Helm")
    func deduplicatesOverlappingMFP() {
        let helm = helmMeal(kcal: 500)
        let mfp = externalMeal(kcal: 495, offsetMinutes: 5)

        let merged = DietarySourceMerger.meals(from: [helm, mfp], mode: .mergeExternal)

        #expect(merged.count == 1)
        #expect(merged[0].source == .manual)
        #expect(merged[0].energy?.kilocalories == 500)
    }

    @Test("external meal kept when kcal outside tolerance")
    func keepsDistinctKcal() {
        let helm = helmMeal(kcal: 500)
        let mfp = externalMeal(kcal: 700, offsetMinutes: 5)

        let merged = DietarySourceMerger.meals(from: [helm, mfp], mode: .mergeExternal)

        #expect(merged.count == 2)
    }

    @Test("external meal kept when time outside window")
    func keepsDistinctTime() {
        let helm = helmMeal(kcal: 500)
        let mfp = externalMeal(kcal: 500, offsetMinutes: 20)

        let merged = DietarySourceMerger.meals(from: [helm, mfp], mode: .mergeExternal)

        #expect(merged.count == 2)
    }

    @Test("helm only mode drops external meals")
    func helmOnlyFiltersExternal() {
        let helm = helmMeal(kcal: 500)
        let mfp = externalMeal(kcal: 800, offsetMinutes: 60)

        let merged = DietarySourceMerger.meals(from: [helm, mfp], mode: .helmOnly)

        #expect(merged.count == 1)
        #expect(merged[0].source == .manual)
    }

    @Test("ingest skips external when Helm overlap exists")
    func skipsIngestOnOverlap() {
        let helm = helmMeal(kcal: 600)
        let mfp = externalMeal(kcal: 610)

        #expect(
            DietarySourceMerger.shouldSkipExternalIngest(
                mfp,
                existingMeals: [helm],
                mode: .mergeExternal
            )
        )

        #expect(
            DietarySourceMerger.shouldSkipExternalIngest(
                mfp,
                existingMeals: [helm],
                mode: .helmOnly
            )
        )
    }
}
