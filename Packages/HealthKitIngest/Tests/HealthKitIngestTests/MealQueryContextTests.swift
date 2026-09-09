import CoachLLM
import Core
import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Meal query context")
struct MealQueryContextTests {
    @Test("parses meal ids from query results")
    func parsesMealIDs() {
        let mealID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let results = """
        query=bucketOnDay day=2026-09-07 bucket=dinner
        id=\(mealID.uuidString.lowercased()) bucket=dinner name=Chicken kcal=500 P=40 C=30 F=20
        """
        let context = MealQueryContext.from(
            query: MealQueryPayload(queryType: .bucketOnDay, helmDay: "2026-09-07", bucket: "dinner"),
            results: results
        )
        #expect(context.mealIDs == [mealID])
        #expect(context.helmDay?.formatted == "2026-09-07")
        #expect(context.bucket == .dinner)
    }
}
