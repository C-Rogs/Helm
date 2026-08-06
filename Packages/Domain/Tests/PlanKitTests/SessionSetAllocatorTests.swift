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
}
