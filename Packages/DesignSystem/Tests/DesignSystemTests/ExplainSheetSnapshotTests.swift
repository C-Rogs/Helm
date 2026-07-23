import Testing
@testable import DesignSystem

@Suite("ExplainSheet snapshots")
struct ExplainSheetSnapshotTests {
    @Test("readiness fixture snapshot")
    func readinessSnapshot() {
        let text = ExplainableMetricSnapshot.text(for: .readinessFixture)

        #expect(text == readinessSnapshotText)
        #expect(text.contains("# Readiness"))
        #expect(text.contains("## ARC Score"))
        #expect(text.contains("61"))
        #expect(text.contains("HRV: z +0.5"))
        #expect(text.contains("enabled=true"))
        #expect(text.contains("Why is my ARC score 61 today?"))
    }

    @Test("prescription volume fixture snapshot")
    func prescriptionVolumeSnapshot() {
        let text = ExplainableMetricSnapshot.text(for: .prescriptionVolumeFixture)

        #expect(text == prescriptionVolumeSnapshotText)
        #expect(text.contains("# Prescription"))
        #expect(text.contains("## Session volume"))
        #expect(text.contains("14 sets"))
        #expect(text.contains("Readiness gate: -4 sets"))
        #expect(text.contains("Why is today's session 14 sets instead of 18?"))
    }

    @Test("nutrition target fixture snapshot")
    func nutritionTargetSnapshot() {
        let text = ExplainableMetricSnapshot.text(for: .nutritionTargetFixture)

        #expect(text == nutritionSnapshotText)
        #expect(text.contains("# Nutrition"))
        #expect(text.contains("## Calorie target"))
        #expect(text.contains("2,760 kcal"))
        #expect(text.contains("Protein floor: 150 g"))
        #expect(text.contains("Why is my calorie target 2,760 kcal today?"))
    }

    @Test("offline fixture disables coach hand-off")
    func offlineSnapshot() {
        let text = ExplainableMetricSnapshot.text(for: .readinessOfflineFixture)

        #expect(text.contains("enabled=false"))
        #expect(text.contains("HRV: z +0.5"))
        #expect(!text.contains("enabled=true"))
    }

    @Test("snapshot text is byte-stable across calls")
    func snapshotByteStable() {
        let first = ExplainableMetricSnapshot.text(for: .readinessFixture)
        let second = ExplainableMetricSnapshot.text(for: .readinessFixture)

        #expect(first == second)
        #expect(first.utf8.elementsEqual(second.utf8))
    }
}

private let readinessSnapshotText = """
# Readiness
## ARC Score
61
state=ready
summary=Balanced recovery with typical HRV and solid sleep.
## Contributors
- HRV: z +0.5 | Above baseline | state=ready
- Resting HR: z -0.1 | Near baseline | state=ready
- Sleep: z +0.3 | Near baseline | state=ready
- Strain: z -0.4 | Below baseline | state=compromised
## Citation
ev-readiness-arc · ARC method
## Coach hand-off
enabled=true
prompt=Why is my ARC score 61 today?
"""

private let prescriptionVolumeSnapshotText = """
# Prescription
## Session volume
14 sets
state=compromised
summary=Volume trimmed because readiness is depleted.
## Contributors
- Baseline: 18 sets | Mesocycle target
- Readiness gate: -4 sets | Low ARC trim | state=depleted
- Phase: Gain | Week 3 accumulating
## Citation
ev-volume-landmarks · MEV to MRV
## Coach hand-off
enabled=true
prompt=Why is today's session 14 sets instead of 18?
"""

private let nutritionSnapshotText = """
# Nutrition
## Calorie target
2,760 kcal
state=ready
summary=Gain phase training day with 150g protein.
## Contributors
- Maintenance: 2,475 kcal | 33 kcal/kg at 75 kg
- Phase surplus: +300 kcal | Gain phase
- Protein floor: 150 g | 2.0 g/kg
- Day type: Training | Higher carb share
## Citation
ev-energy-balance · Energy balance
## Coach hand-off
enabled=true
prompt=Why is my calorie target 2,760 kcal today?
"""
