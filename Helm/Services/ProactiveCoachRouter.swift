import Foundation

@MainActor
enum ProactiveCoachRouter {
    static func surface(
        _ message: String,
        sessionID: String?,
        on controller: TrainSessionController
    ) {
        if ProactiveCoachPreferences.peekEnabled {
            controller.setCoachPeekSnippet(message)
        }
        if ProactiveCoachPreferences.bannerEnabled {
            controller.setProactiveCoachBanner(message)
        }
        if ProactiveCoachPreferences.autoChatEnabled {
            controller.insertProactiveCoachMessage(message)
        }
        if ProactiveCoachPreferences.pushEnabled, let sessionID {
            Task {
                await ProactiveBootstrap.notificationScheduler.postIntraWorkoutCoach(
                    message: message,
                    sessionID: sessionID
                )
            }
        }
    }
}
