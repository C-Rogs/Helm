import Core
import Testing
@testable import HealthKitIngest

@Suite("Meal diary op echo")
struct MealDiaryOpEchoTests {
    @Test("deleted echo includes ISO day, bucket, and count")
    func deletedEcho() {
        let day = HelmDay(year: 2026, month: 9, day: 6)
        #expect(
            MealDiaryOpEcho.deleted(count: 6, day: day, bucket: .dinner)
                == "deleted 6 meals on 2026-09-06 dinner"
        )
        #expect(
            MealDiaryOpEcho.deleted(count: 1, day: day, bucket: nil)
                == "deleted 1 meal on 2026-09-06"
        )
    }

    @Test("copied echo includes source and target ISO days")
    func copiedEcho() {
        let source = HelmDay(year: 2026, month: 9, day: 6)
        let target = HelmDay(year: 2026, month: 9, day: 8)
        #expect(
            MealDiaryOpEcho.copied(
                count: 6,
                source: source,
                sourceBucket: .dinner,
                target: target,
                targetBucket: .dinner
            ) == "copied 6 meals from 2026-09-06 dinner → 2026-09-08 dinner"
        )
    }
}
