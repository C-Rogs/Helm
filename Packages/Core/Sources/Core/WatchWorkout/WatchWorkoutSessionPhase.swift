import Foundation

public enum WatchWorkoutSessionPhase: Equatable, Sendable {
    case idle
    case preparing
    case active
    case paused
    case ending
    case ended
}

public enum WatchWorkoutSessionEvent: Equatable, Sendable {
    case startRequested
    case sessionReady
    case pause
    case resume
    case endRequested
    case discardRequested
    case teardownSucceeded
    case teardownFailed
}

public enum WatchWorkoutSessionReducer {
    public static func reduce(
        phase: WatchWorkoutSessionPhase,
        event: WatchWorkoutSessionEvent
    ) -> WatchWorkoutSessionPhase? {
        switch (phase, event) {
        case (.idle, .startRequested), (.ended, .startRequested):
            return .preparing
        case (.preparing, .sessionReady):
            return .active
        case (.preparing, .teardownFailed), (.preparing, .discardRequested):
            return .idle
        case (.active, .pause):
            return .paused
        case (.active, .endRequested), (.active, .discardRequested):
            return .ending
        case (.paused, .resume):
            return .active
        case (.paused, .endRequested), (.paused, .discardRequested):
            return .ending
        case (.ending, .teardownSucceeded):
            return .ended
        case (.ending, .teardownFailed):
            return .idle
        default:
            return nil
        }
    }

    public enum TeardownStep: Equatable, Sendable, CaseIterable {
        case endCollection
        case finishWorkout
        case discardWorkout
        case endSession
    }

    public static func teardownSteps(discard: Bool) -> [TeardownStep] {
        discard
            ? [.endCollection, .discardWorkout, .endSession]
            : [.endCollection, .finishWorkout, .endSession]
    }
}
