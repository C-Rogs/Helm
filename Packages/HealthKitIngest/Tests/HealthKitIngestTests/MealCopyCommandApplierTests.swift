import CoachLLM
import Core
import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Meal copy command applier")
struct MealCopyCommandApplierTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = HelmDay(year: 2026, month: 9, day: 9)

    @Test("defaults missing target day to today")
    func defaultsTargetDayToToday() {
        let payload = MealCopyPayload(
            reply: "Copying dinner.",
            sourceHelmDay: "2026-09-07",
            sourceBucket: "dinner",
            targetHelmDay: "",
            targetBucket: "dinner"
        )
        let resolved = MealCopyCommandApplier.resolvedDays(payload, today: today, calendar: calendar)
        #expect(resolved?.target == today)
        #expect(resolved?.source.formatted == "2026-09-07")
    }

    @Test("preview uses formatted day labels")
    func previewUsesFormattedLabels() {
        let payload = MealCopyPayload(
            reply: "Copying dinner.",
            sourceHelmDay: "2026-09-07",
            sourceBucket: "dinner",
            targetHelmDay: "2026-09-09",
            targetBucket: "dinner"
        )
        let preview = MealCopyCommandApplier.preview(for: payload, today: today, calendar: calendar)
        #expect(preview.detail.contains("2026-09-07"))
        #expect(preview.detail.contains("2026-09-09"))
    }
}
