import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Session set allocator")
struct SessionSetAllocatorTests {
    private func candidate(
        muscle: MuscleGroup = .chest,
        role: PatternSlotRole = .primary,
        required: Bool = true
    ) -> SlotAllocationCandidate {
        SlotAllocationCandidate(
            slot: PatternSlot(
                index: 0,
                pattern: .horizontalPress,
                primaryMuscle: muscle,
                role: role,
                required: required
            ),
            exercise: CatalogExercise(
                exerciseID: "bench_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bench_press",
                    contributions: [ExerciseMuscleContribution(muscle: muscle, fraction: 1.0)]
                ),
                priority: 0
            ),
            rationale: "test",
            evidenceIDs: []
        )
    }

    @Test("zero remaining muscle volume allocates zero sets")
    func zeroRemainingVolume() {
        let allocations = SessionSetAllocator.allocate(
            candidates: [candidate()],
            budget: .minutes60,
            thinSession: false,
            volumeMultiplier: 1.0,
            remainingByMuscle: [.chest: 0]
        )

        #expect(allocations.isEmpty)
    }

    @Test("non-finite volume multiplier does not trap")
    func nonFiniteVolumeMultiplier() {
        let allocations = SessionSetAllocator.allocate(
            candidates: [candidate()],
            budget: .minutes60,
            thinSession: true,
            volumeMultiplier: .nan,
            remainingByMuscle: [.chest: 10]
        )

        #expect(!allocations.isEmpty)
    }

    @Test("volume multiplier caps total sets when remaining is plentiful")
    func volumeMultiplierCapsSession() {
        let candidates = [
            candidate(muscle: .chest, role: .primary),
            candidate(muscle: .shoulders, role: .primary),
            candidate(muscle: .chest, role: .secondary)
        ]
        let full = SessionSetAllocator.allocate(
            candidates: candidates,
            budget: .minutes30,
            thinSession: false,
            volumeMultiplier: 1.0,
            remainingByMuscle: [.chest: 20, .shoulders: 20]
        )
        let cut = SessionSetAllocator.allocate(
            candidates: candidates,
            budget: .minutes30,
            thinSession: false,
            volumeMultiplier: 0.85,
            remainingByMuscle: [.chest: 20, .shoulders: 20]
        )
        let fullSets = full.reduce(0) { $0 + $1.sets }
        let cutSets = cut.reduce(0) { $0 + $1.sets }
        #expect(cutSets < fullSets)
    }
}
