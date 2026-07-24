import Testing
@testable import DesignSystem

@Suite("Progression detail snapshots")
struct ProgressionDetailSnapshotTests {
    @Test("mid-meso fixture snapshot")
    func midMesoSnapshot() {
        let text = ProgressionDetailSnapshot.text(for: .midMesoFixture)
        #expect(text == midMesoSnapshotText)
        #expect(text.contains("deload=false"))
    }

    @Test("deload week fixture snapshot")
    func deloadSnapshot() {
        let text = ProgressionDetailSnapshot.text(for: .deloadWeekFixture)
        #expect(text == deloadWeekSnapshotText)
        #expect(text.contains("deload=true"))
    }

    @Test("cold start fixture snapshot")
    func coldStartSnapshot() {
        let text = ProgressionDetailSnapshot.text(for: .coldStartFixture)
        #expect(text == coldStartSnapshotText)
        #expect(text.contains("coldStart=true"))
    }
}

private let midMesoSnapshotText = """
# Progression
## Block
phase=Gain · v-taper
experience=Intermediate
summary=Week 3 of 5 · Accumulating
deload=false
coldStart=false
## Scheme
repRange=8-12
rpeCap=RPE 8.5
targetRPE=RPE 8.0
loadIncrement=+2.5%
setsPerSession=3-4 / exercise
## Mesocycle
- Chest: week 3/5 | Accumulating | target 14 | done 10 | MEV 8 MRV 18 | state=ready
- Back: week 3/5 | Accumulating | target 16 | done 12 | MEV 8 MRV 20 | state=ready
- Quads: week 3/5 | Accumulating | target 15 | done 6 | MEV 8 MRV 20 | state=depleted
## Ladders
- Bench Press (Barbell): e1RM=102.5 working=82.0 reps=8-12
  - step 1: 95 kg e1RM | e1RM=95.0 | delta=nil | completed=true
  - step 2: 98 kg e1RM | e1RM=98.0 | delta=3.0 | completed=true
  - step 3: 102 kg e1RM | e1RM=102.5 | delta=4.5 | completed=true
  - step 4: Next: 82 kg × 8-12 | e1RM=nil | delta=nil | completed=false
- Squat (Barbell): e1RM=140.0 working=112.5 reps=8-12
  - step 1: 128 kg e1RM | e1RM=128.0 | delta=nil | completed=true
  - step 2: 140 kg e1RM | e1RM=140.0 | delta=12.0 | completed=true
  - step 3: Next: 112.5 kg × 8-12 | e1RM=nil | delta=nil | completed=false
"""

private let deloadWeekSnapshotText = """
# Progression
## Block
phase=Maintain
experience=Intermediate
summary=Week 5 of 5 · Deload
deload=true
coldStart=false
## Scheme
repRange=8-12
rpeCap=RPE 7.0
targetRPE=RPE 6.5
loadIncrement=+2.5%
setsPerSession=2-3 / exercise
## Mesocycle
- Chest: week 5/5 | Deload | target 9 | done 4 | MEV 8 MRV 18 | state=ready
- Back: week 5/5 | Deload | target 10 | done 6 | MEV 8 MRV 20 | state=ready
## Ladders
- Bench Press (Barbell): e1RM=102.5 working=80.0 reps=8-12
  - step 1: 102 kg e1RM | e1RM=102.5 | delta=nil | completed=true
  - step 2: Deload: 80 kg × 8-12 | e1RM=nil | delta=nil | completed=false
"""

private let coldStartSnapshotText = """
# Progression
## Block
phase=Gain
experience=Novice
summary=Week 1 of 5 · Accumulating
deload=false
coldStart=true
## Scheme
repRange=8-12
rpeCap=RPE 8.5
targetRPE=RPE 8.0
loadIncrement=+2.5%
setsPerSession=3 / exercise
## Mesocycle
- Chest: week 1/5 | Accumulating | target 7 | done 0 | MEV 7 MRV 15 | state=depleted
- Back: week 1/5 | Accumulating | target 7 | done 0 | MEV 7 MRV 17 | state=depleted
## Ladders
- none
"""
