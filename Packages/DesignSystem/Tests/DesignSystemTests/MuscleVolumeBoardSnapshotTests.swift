import DesignSystem
import Testing

@Suite("Muscle volume board")
struct MuscleVolumeBoardSnapshotTests {
    @Test("state coverage fixture includes all volume bands")
    func stateCoverageFixture() {
        let rows = MuscleVolumeBoardModel.stateCoverageFixture.rows
        #expect(rows.contains { $0.state == .depleted })
        #expect(rows.contains { $0.state == .ready })
        #expect(rows.contains { $0.state == .primed })
        #expect(rows.contains { $0.state == .compromised })

        for row in rows {
            #expect(HelmState.volumeWeekly(sets: row.weeklySets, mev: row.mev, mrv: row.mrv) == row.state)
            let status = VolumeLandmarkStatus.resolve(sets: row.weeklySets, mev: row.mev, mrv: row.mrv)
            #expect(["below MEV", "in range", "over MRV"].contains(status.label))
        }
    }

    @Test("load window labels describe rolling seven days")
    func loadWindowLabels() {
        #expect(MuscleVolumeBoardModel.loadWindowDays == 7)
        #expect(MuscleVolumeBoardModel.loadWindowTitle == "7-day volume")
        #expect(MuscleVolumeBoardModel.loadWindowSubtitle.contains("Logged + scheduled"))
        #expect(MuscleVolumeBoardModel.loadWindowSubtitle.contains("projected"))
    }

    @Test("recency labels cover trained and never-trained muscles")
    func recencyLabels() {
        #expect(MuscleVolumeRecency.label(daysSinceTrained: 0) == "Today")
        #expect(MuscleVolumeRecency.label(daysSinceTrained: 3) == "3d ago")
        #expect(MuscleVolumeRecency.label(daysSinceTrained: nil) == "Never")
        #expect(MuscleVolumeRecency.shortLabel(daysSinceTrained: 2) == "2d")
    }
}
