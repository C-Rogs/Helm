import Core
import Foundation
import Testing
@testable import NutritionKit

@Suite("Body profile TDEE")
struct BodyProfileTDEETests {
    private func profile(
        mass: Double = 75,
        height: Double = 175,
        sex: BiologicalSex = .male,
        ageYears: Int = 30
    ) -> BodyProfile {
        let calendar = Calendar(identifier: .gregorian)
        let dob = calendar.date(byAdding: .year, value: -ageYears, to: Date())!
        return BodyProfile(
            bodyMassKg: mass,
            heightCm: height,
            biologicalSex: sex,
            dateOfBirth: dob
        )
    }

    @Test("Mifflin-St Jeor seed uses weight, height, sex, and age")
    func mifflinSeed() throws {
        let male = profile(mass: 75, height: 175, sex: .male, ageYears: 30)
        let female = profile(mass: 75, height: 175, sex: .female, ageYears: 30)

        let maleTDEE = try #require(BodyProfileTDEE.seedTDEEKcal(profile: male))
        let femaleTDEE = try #require(BodyProfileTDEE.seedTDEEKcal(profile: female))

        #expect(maleTDEE > femaleTDEE)
        #expect(maleTDEE > 1_500)
    }

    @Test("incomplete profile yields no seed TDEE")
    func incompleteProfile() {
        var incomplete = profile()
        incomplete.bodyMassKg = 0
        #expect(BodyProfileTDEE.seedTDEEKcal(profile: incomplete) == nil)
    }
}
