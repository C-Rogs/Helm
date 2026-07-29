import Core
import Testing
@testable import HealthKitIngest

@Suite("Emphasis volume policy")
struct EmphasisVolumePolicyTests {
    @Test("arm emphasis adds biceps and triceps without replacing split muscles")
    func armEmphasisAddsSlots() {
        let base: [MuscleGroup] = [.chest, .shoulders, .triceps]
        let augmented = EmphasisVolumePolicy.augmentedTargetMuscles(base: base, emphasis: "Arms")
        #expect(augmented.contains(.biceps))
        #expect(augmented.contains(.triceps))
        #expect(augmented.contains(.chest))
    }

    @Test("empty emphasis leaves targets unchanged")
    func noEmphasis() {
        let base: [MuscleGroup] = [.back, .biceps]
        #expect(
            EmphasisVolumePolicy.augmentedTargetMuscles(base: base, emphasis: nil) == base
        )
    }
}
