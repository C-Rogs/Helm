import AppIntents
import Foundation

enum LiveActivityCompleteSetBridge {
    static let notificationName = Notification.Name("com.cameronro.helm.liveActivity.completeSet")
    static let sessionExerciseIDKey = "sessionExerciseID"
    static let setIDKey = "setID"
}

/// Completes the current set from the Live Activity Done chip (runs in the app process).
struct CompleteLiveActivitySetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete set"
    static let description = IntentDescription("Marks the current Train set complete from the Live Activity.")

    @Parameter(title: "Session Exercise ID")
    var sessionExerciseID: String

    @Parameter(title: "Set ID")
    var setID: String

    init() {
        sessionExerciseID = ""
        setID = ""
    }

    init(sessionExerciseID: String, setID: String) {
        self.sessionExerciseID = sessionExerciseID
        self.setID = setID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard !sessionExerciseID.isEmpty, !setID.isEmpty else {
            return .result()
        }
        NotificationCenter.default.post(
            name: LiveActivityCompleteSetBridge.notificationName,
            object: nil,
            userInfo: [
                LiveActivityCompleteSetBridge.sessionExerciseIDKey: sessionExerciseID,
                LiveActivityCompleteSetBridge.setIDKey: setID
            ]
        )
        return .result()
    }
}
