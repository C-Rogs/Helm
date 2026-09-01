import AppIntents
import HealthKitIngest

struct GenerateBriefIntent: AppIntent {
    static let title: LocalizedStringResource = "Generate Morning Brief"
    static let description = IntentDescription(
        "Harvest health data, compute readiness, and deliver your morning brief as a notification."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await BriefIntentBootstrap.runner.run()

        switch outcome {
        case .lockedPhone:
            return .result(dialog: "Phone locked. Open Signal for your brief.")
        case .succeeded:
            return .result(dialog: "Morning brief ready.")
        case .timedOut:
            return .result(dialog: "Brief timed out. Open Signal to finish.")
        case let .failed(message):
            return .result(dialog: "Brief failed: \(message)")
        }
    }
}

struct HelmShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GenerateBriefIntent(),
            phrases: [
                "Generate my morning brief in \(.applicationName)",
                "Run morning brief in \(.applicationName)",
                "Morning brief with \(.applicationName)"
            ],
            shortTitle: "Morning Brief",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: LogUsualMealIntent(meal: .breakfast),
            phrases: [
                "Log my usual breakfast in \(.applicationName)",
                "Log usual breakfast in \(.applicationName)"
            ],
            shortTitle: "Usual breakfast",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogUsualMealIntent(meal: .lunch),
            phrases: [
                "Log my usual lunch in \(.applicationName)",
                "Log usual lunch in \(.applicationName)"
            ],
            shortTitle: "Usual lunch",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogUsualMealIntent(meal: .dinner),
            phrases: [
                "Log my usual dinner in \(.applicationName)",
                "Log usual dinner in \(.applicationName)"
            ],
            shortTitle: "Usual dinner",
            systemImageName: "fork.knife"
        )
    }
}
