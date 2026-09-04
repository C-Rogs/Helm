import os

public enum HelmSignpostName: Sendable {
    case healthKitObserverFetch
    case backfillChunk
    case readinessCompute
    case prescriptionCompute
    case geminiStream
    case inSessionCoachPropose
    case briefIntentRun
    case workoutSessionLifecycle
    case liveWorkoutBuilderTeardown
    case patternEvaluate
}

public struct HelmSignpost: Sendable {
    public let name: HelmSignpostName
    public let category: HelmCategory
    private let log: OSLog

    public init(name: HelmSignpostName, category: HelmCategory) {
        self.name = name
        self.category = category
        log = OSLog(subsystem: HelmSubsystem.value, category: category.rawValue)
    }

    public func makeSignpostID() -> OSSignpostID {
        OSSignpostID(log: log)
    }

    public func begin(id: OSSignpostID) {
        os_signpost(.begin, log: log, name: staticName, signpostID: id)
    }

    public func end(id: OSSignpostID) {
        os_signpost(.end, log: log, name: staticName, signpostID: id)
    }

    public func event(id: OSSignpostID) {
        os_signpost(.event, log: log, name: staticName, signpostID: id)
    }

    private var staticName: StaticString {
        switch name {
        case .healthKitObserverFetch: "HealthKitObserverFetch"
        case .backfillChunk: "BackfillChunk"
        case .readinessCompute: "ReadinessCompute"
        case .prescriptionCompute: "PrescriptionCompute"
        case .geminiStream: "GeminiStream"
        case .inSessionCoachPropose: "InSessionCoachPropose"
        case .briefIntentRun: "BriefIntentRun"
        case .workoutSessionLifecycle: "WorkoutSessionLifecycle"
        case .liveWorkoutBuilderTeardown: "LiveWorkoutBuilderTeardown"
        case .patternEvaluate: "PatternEvaluate"
        }
    }
}
