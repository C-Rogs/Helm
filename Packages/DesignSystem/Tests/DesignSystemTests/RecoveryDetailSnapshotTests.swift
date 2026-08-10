import Testing
@testable import DesignSystem

@Suite("Recovery detail snapshots")
struct RecoveryDetailSnapshotTests {
    @Test("good recovery fixture snapshot")
    func goodSnapshot() {
        let text = RecoveryDetailSnapshot.text(for: .goodFixture)

        #expect(text == goodRecoverySnapshotText)
        #expect(text.contains("state=primed"))
        #expect(text.contains("HRV: 48.2 ms"))
        #expect(text.contains("enabled=true"))
    }

    @Test("compromised recovery fixture snapshot")
    func compromisedSnapshot() {
        let text = RecoveryDetailSnapshot.text(for: .compromisedFixture)

        #expect(text == compromisedRecoverySnapshotText)
        #expect(text.contains("state=compromised"))
        #expect(text.contains("verdictTag=LOW") == false)
        #expect(text.contains("| LOW"))
        #expect(text.contains("engineOnly=true"))
    }

    @Test("cold start fixture snapshot")
    func coldStartSnapshot() {
        let text = RecoveryDetailSnapshot.text(for: .coldStartFixture)

        #expect(text == coldStartRecoverySnapshotText)
        #expect(text.contains("band=building"))
        #expect(text.contains("PROVISIONAL"))
        #expect(text.contains("validNights=6"))
    }

    @Test("stale resting HR fixture snapshot")
    func staleRestingHRSnapshot() {
        let text = RecoveryDetailSnapshot.text(for: .staleRestingHRFixture)

        #expect(text == staleRestingHRRecoverySnapshotText)
        #expect(text.contains("YESTERDAY"))
        #expect(text.contains("from Apple Health"))
        #expect(text.contains("| muted"))
    }

    @Test("offline fixture disables coach hand-off")
    func offlineSnapshot() {
        let text = RecoveryDetailSnapshot.text(for: .offlineFixture)

        #expect(text.contains("enabled=false"))
        #expect(text.contains("engineOnly=true"))
        #expect(!text.contains("enabled=true"))
    }

    @Test("snapshot text is byte-stable across calls")
    func snapshotByteStable() {
        let first = RecoveryDetailSnapshot.text(for: .goodFixture)
        let second = RecoveryDetailSnapshot.text(for: .goodFixture)

        #expect(first == second)
        #expect(first.utf8.elementsEqual(second.utf8))
    }
}

private let goodRecoverySnapshotText = """
# Recovery
## ARC Score
72
state=primed
targetBand=67-100
narration=Push today: 16 sets across 5 exercises. Fuel with 2400 kcal and 180g protein.
engineOnly=false
validNights=18
citation=ev-readiness-arc
## Contributors
- HRV: 48.2 ms | band 44.3-49.3 | GOOD | state=ready
- Resting HR: 51 bpm | band 48-54 | GOOD | from Apple Health | state=ready
- Sleep: 7.4 h | band 6.8-7.6 | GOOD | state=ready
## History
- Jul 10: 55 | state=ready
- Jul 17: 68 | state=ready
- Jul 23: 72 | state=primed
## Coach hand-off
enabled=true
prompt=Why is my ARC score 72 today?
"""

private let compromisedRecoverySnapshotText = """
# Recovery
## ARC Score
41
state=compromised
targetBand=34-66
narration=Balanced recovery with 16 baseline nights.
engineOnly=true
validNights=16
## Contributors
- HRV: 38.5 ms | band 44.3-49.3 | LOW | state=depleted
- Resting HR: 58 bpm | band 48-54 | HIGH | state=compromised
- Sleep: 5.9 h | band 6.8-7.6 | LOW | state=depleted
## History
- Jul 10: 62 | state=ready
- Jul 17: 48 | state=compromised
- Jul 23: 41 | state=compromised
## Coach hand-off
enabled=true
prompt=Why is my ARC score 41 today?
"""

private let coldStartRecoverySnapshotText = """
# Recovery
## ARC Score
58
state=ready
targetBand=34-66
narration=Provisional score with 6/14 baseline nights.
engineOnly=true
validNights=6
## Contributors
- HRV: 42.1 ms | band=building | PROVISIONAL | state=ready
- Resting HR: 54 bpm | band=building | PROVISIONAL | state=ready
- Sleep: 6.8 h | band=building | PROVISIONAL | state=ready
## History
- Jul 20: 52 | state=ready
- Jul 23: 58 | state=ready
## Coach hand-off
enabled=true
prompt=Why is my ARC score 58 today?
"""

private let staleRestingHRRecoverySnapshotText = """
# Recovery
## ARC Score
68
state=ready
targetBand=34-66
narration=Balanced recovery with 14 baseline nights.
engineOnly=true
validNights=14
## Contributors
- HRV: 47.0 ms | band 44.3-49.3 | TYPICAL | state=ready
- Resting HR: 53 bpm | band 48-54 | YESTERDAY | from Apple Health | muted | state=ready
- Sleep: 7.2 h | band 6.8-7.6 | TYPICAL | state=ready
## History
- Jul 22: 64 | state=ready
- Jul 23: 68 | state=ready
## Coach hand-off
enabled=true
prompt=Why is my ARC score 68 today?
"""
