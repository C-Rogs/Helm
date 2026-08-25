import Foundation
import ReadinessKit
import Testing
@testable import PlanKit

@Suite("Session composer property tests")
struct SessionComposerPropertyTests {
    @Test("duration budgets cap slot count for every day kind and template")
    func durationBudgetCapsSlots() {
        let bands: [ReadinessBand?] = [nil, .primed, .balanced, .depleted]
        for dayKind in TrainingDayKind.allCases {
            for budget in SessionDurationBudget.allCases {
                for template in ProgramTemplate.allCases {
                    for band in bands {
                        for isDeload in [false, true] {
                            let slots = SessionComposer.slots(
                                dayKind: dayKind,
                                budget: budget,
                                template: template,
                                readinessBand: band,
                                isDeload: isDeload
                            )
                            #expect(slots.count <= budget.maxSlots)
                            #expect(slots.count >= 1)
                            let indices = slots.map(\.index)
                            #expect(indices == Array(0 ..< slots.count))

                            let thin = SessionComposer.allowsThinSession(
                                budget: budget,
                                readinessBand: band,
                                isDeload: isDeload
                            )
                            let full = SessionComposer.slots(
                                dayKind: dayKind,
                                budget: .minutes75,
                                template: template,
                                readinessBand: .primed,
                                isDeload: false
                            )
                            let capped = Array(full.prefix(budget.maxSlots))
                            if thin {
                                let keep = max(2, min(capped.count, budget == .minutes30 ? 2 : budget.maxSlots - 2))
                                #expect(slots.map(\.pattern) == Array(capped.map(\.pattern).prefix(keep)))
                            } else {
                                #expect(slots.map(\.pattern) == capped.map(\.pattern))
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("non-thin UL/FB sessions keep required pattern vectors")
    func requiredPatternVectors() {
        for budget in SessionDurationBudget.allCases where budget != .minutes30 {
            let upper = SessionComposer.slots(
                dayKind: .upper,
                budget: budget,
                template: .upperLower,
                readinessBand: .balanced,
                isDeload: false
            )
            let upperPatterns = Set(upper.map(\.pattern))
            #expect(upperPatterns.contains(.horizontalPress))
            #expect(upperPatterns.contains(.verticalPull))

            let lower = SessionComposer.slots(
                dayKind: .lower,
                budget: budget,
                template: .upperLower,
                readinessBand: .balanced,
                isDeload: false
            )
            let lowerPatterns = Set(lower.map(\.pattern))
            #expect(lowerPatterns.contains(.kneeExtensionCompound))
            #expect(lowerPatterns.contains(.hipHinge))

            let full = SessionComposer.slots(
                dayKind: .full,
                budget: budget,
                template: .fullBody,
                readinessBand: .balanced,
                isDeload: false
            )
            let fullPatterns = Set(full.map(\.pattern))
            #expect(fullPatterns.contains(.kneeExtensionCompound))
            #expect(fullPatterns.contains(.horizontalPress))
            #expect(fullPatterns.contains(.verticalPull) || fullPatterns.contains(.horizontalPull))
        }
    }

    @Test("depleted and deload trim the same way across templates")
    func thinTrimIsTemplateAgnostic() {
        for dayKind: TrainingDayKind in [.upper, .lower, .full] {
            let depleted = SessionComposer.slots(
                dayKind: dayKind,
                budget: .minutes60,
                template: .ppl,
                readinessBand: .depleted,
                isDeload: false
            )
            let deload = SessionComposer.slots(
                dayKind: dayKind,
                budget: .minutes60,
                template: .upperLower,
                readinessBand: .balanced,
                isDeload: true
            )
            let normal = SessionComposer.slots(
                dayKind: dayKind,
                budget: .minutes60,
                template: .fullBody,
                readinessBand: .balanced,
                isDeload: false
            )
            #expect(depleted.count == deload.count)
            #expect(depleted.count < normal.count)
            #expect(depleted.count <= 3)
        }
    }
}
