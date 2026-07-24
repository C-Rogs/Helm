import Core
import Foundation
import Testing
@testable import HealthKitIngest

@Suite("HealthKit day aggregator")
struct HealthKitDayAggregatorTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private let day = HelmDay(year: 2026, month: 7, day: 21)

    @Test("averages HRV samples per helm day")
    func hrvAverage() throws {
        let morning = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 8))
        )
        let samples = [
            IngestQuantitySample(
                id: UUID(),
                start: morning,
                end: morning,
                value: 40,
                unitSymbol: "ms",
                sourceBundleID: "com.apple.health"
            ),
            IngestQuantitySample(
                id: UUID(),
                start: morning.addingTimeInterval(3_600),
                end: morning.addingTimeInterval(3_600),
                value: 60,
                unitSymbol: "ms",
                sourceBundleID: "com.apple.health"
            )
        ]

        let patches = HealthKitDayAggregator.aggregateQuantity(
            kind: .hrvSDNN,
            samples: samples,
            calendar: calendar
        )

        #expect(patches.count == 1)
        #expect(patches[0].helmDay == day)
        #expect(patches[0].hrvSDNN?.milliseconds == 50)
    }

    @Test("sums dietary energy in kilocalories")
    func dietaryEnergySum() throws {
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 12))
        )
        let samples = [
            IngestQuantitySample(
                id: UUID(),
                start: loggedAt,
                end: loggedAt,
                value: 500,
                unitSymbol: "kcal",
                sourceBundleID: "com.myfitnesspal.mfp"
            ),
            IngestQuantitySample(
                id: UUID(),
                start: loggedAt.addingTimeInterval(60),
                end: loggedAt.addingTimeInterval(60),
                value: 300,
                unitSymbol: "kcal",
                sourceBundleID: "com.myfitnesspal.mfp"
            )
        ]

        let patches = HealthKitDayAggregator.aggregateQuantity(
            kind: .dietaryEnergy,
            samples: samples,
            calendar: calendar
        )

        #expect(patches[0].dietaryEnergy?.kilocalories == 800)
    }

    @Test("explicit alcohol kcal is excluded from macro gap")
    func explicitAlcoholExcluded() {
        let meals = [
            MealRecord(
                helmDay: day,
                name: "Beer",
                loggedAt: Date(),
                energy: Energy(kilocalories: 420),
                proteinGrams: 4,
                carbohydrateGrams: 34,
                fatGrams: 0,
                source: .alcohol
            )
        ]

        let nutritionDay = HealthKitDayAggregator.nutritionDay(from: meals, helmDay: day)

        #expect(nutritionDay.macroGapKilocalories == nil)
    }

    @Test("untracked alcohol from HealthKit still surfaces gap")
    func untrackedAlcoholGap() {
        let meals = [
            MealRecord(
                helmDay: day,
                name: "Beer",
                loggedAt: Date(),
                energy: Energy(kilocalories: 600),
                proteinGrams: 4,
                carbohydrateGrams: 30,
                fatGrams: 0,
                source: .healthKit,
                externalSampleID: UUID().uuidString
            )
        ]

        let nutritionDay = HealthKitDayAggregator.nutritionDay(from: meals, helmDay: day)

        #expect(nutritionDay.macroGapKilocalories != nil)
        #expect(nutritionDay.macroGapKilocalories! > 100)
    }

    @Test("dedupes meal drafts by external sample id")
    func mealDraftDedup() {
        let sampleID = UUID()
        let drafts = [
            IngestMealDraft(
                id: sampleID,
                helmDay: day,
                loggedAt: Date(),
                energy: Energy(kilocalories: 500),
                proteinGrams: nil,
                carbohydrateGrams: nil,
                fatGrams: nil,
                externalSampleID: sampleID.uuidString.lowercased()
            ),
            IngestMealDraft(
                id: sampleID,
                helmDay: day,
                loggedAt: Date(),
                energy: nil,
                proteinGrams: 40,
                carbohydrateGrams: nil,
                fatGrams: nil,
                externalSampleID: sampleID.uuidString.lowercased()
            )
        ]

        let meals = HealthKitDayAggregator.mergeMealDrafts(drafts)

        #expect(meals.count == 1)
        #expect(meals[0].energy?.kilocalories == 500)
        #expect(meals[0].proteinGrams == 40)
    }
}
