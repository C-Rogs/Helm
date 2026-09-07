import Foundation
import Testing
@testable import Core

@Suite("Step goal preferences")
struct StepGoalPreferencesTests {
    @Test("defaults off when unset")
    func defaultDisabled() {
        let suite = "helm.tests.stepGoal.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!StepGoalPreferences.isEnabled(defaults: defaults))
        #expect(StepGoalPreferences.activeGoal(defaults: defaults) == nil)
        #expect(StepGoalPreferences.goalCount(defaults: defaults) == 10_000)
    }

    @Test("enabling seeds default goal")
    func enableSeedsDefault() {
        let suite = "helm.tests.stepGoal.enable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        StepGoalPreferences.setEnabled(true, defaults: defaults)
        #expect(StepGoalPreferences.isEnabled(defaults: defaults))
        #expect(StepGoalPreferences.activeGoal(defaults: defaults) == 10_000)
    }

    @Test("persists goal count")
    func persistsGoal() {
        let suite = "helm.tests.stepGoal.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        StepGoalPreferences.setEnabled(true, defaults: defaults)
        StepGoalPreferences.setGoalCount(8_000, defaults: defaults)
        #expect(StepGoalPreferences.goalCount(defaults: defaults) == 8_000)
        #expect(StepGoalPreferences.activeGoal(defaults: defaults) == 8_000)
    }

    @Test("clamps and snaps goal to step")
    func clampsGoal() {
        let suite = "helm.tests.stepGoal.clamp.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        StepGoalPreferences.setGoalCount(0, defaults: defaults)
        #expect(StepGoalPreferences.goalCount(defaults: defaults) == 1_000)

        StepGoalPreferences.setGoalCount(99_999, defaults: defaults)
        #expect(StepGoalPreferences.goalCount(defaults: defaults) == 50_000)

        StepGoalPreferences.setGoalCount(8_250, defaults: defaults)
        #expect(StepGoalPreferences.goalCount(defaults: defaults) == 8_500)

        defaults.set(77, forKey: StepGoalPreferences.goalCountKey)
        #expect(StepGoalPreferences.goalCount(defaults: defaults) == 1_000)
    }

    @Test("greeting line switches with goal")
    func greetingLine() {
        let suite = "helm.tests.stepGoal.greeting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(
            StepGoalPreferences.greetingStepsLine(stepCount: 4_200, defaults: defaults)
                == "4200 steps"
        )
        #expect(
            StepGoalPreferences.greetingStepsAccessibilityLabel(
                stepCount: 4_200,
                defaults: defaults
            ) == "4200 steps today"
        )

        StepGoalPreferences.setEnabled(true, defaults: defaults)
        StepGoalPreferences.setGoalCount(10_000, defaults: defaults)
        #expect(
            StepGoalPreferences.greetingStepsLine(stepCount: 4_200, defaults: defaults)
                == "4200 / 10000"
        )
        #expect(
            StepGoalPreferences.greetingStepsAccessibilityLabel(
                stepCount: 4_200,
                defaults: defaults
            ) == "4200 of 10000 steps today"
        )
    }
}
