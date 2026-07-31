import Core
import Testing

@Suite("Bodyweight volume (Hevy rules)")
struct BodyweightVolumeTests {
    @Test("barbell volume uses column load only")
    func barbellUsesColumn() {
        #expect(
            BodyweightVolume.setVolumeKg(
                loggedMassKg: 100,
                reps: 5,
                exerciseMode: .weightReps,
                bodyweightKg: 75
            ) == 500
        )
    }

    @Test("full-BW move with no added weight uses athlete BW")
    func fullBWNoAdded() {
        #expect(
            BodyweightVolume.setVolumeKg(
                loggedMassKg: nil,
                reps: 10,
                exerciseMode: .bodyweightReps,
                bodyweightKg: 72.5
            ) == 725
        )
    }

    @Test("full-BW move with belt weight uses BW plus added in column")
    func fullBWWithAdded() {
        #expect(
            BodyweightVolume.effectiveMassKg(
                loggedMassKg: 10,
                exerciseMode: .bodyweightReps,
                bodyweightKg: 72.5
            ) == 82.5
        )
        #expect(
            BodyweightVolume.setVolumeKg(
                loggedMassKg: 10,
                reps: 8,
                exerciseMode: .bodyweightReps,
                bodyweightKg: 72.5
            ) == 660
        )
    }

    @Test("added kg stored separately from total for display")
    func columnIsAddedOnly() {
        #expect(
            BodyweightVolume.effectiveMassKg(
                loggedMassKg: 15,
                exerciseMode: .weightReps,
                bodyweightKg: 72.5
            ) == 15
        )
    }
}
