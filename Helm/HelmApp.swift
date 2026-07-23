import Diagnostics
import DesignSystem
import Persistence
import SwiftUI

@main
struct HelmApp: App {
    @UIApplicationDelegateAdaptor(HelmAppDelegate.self) private var appDelegate

    init() {
        HelmFontRegistration.registerFontsIfNeeded()
        Task { @MainActor in
            await DiagnosticsBootstrap.run()
            await PersistenceBootstrap.logOpen()
            await PersistenceBootstrap.importExerciseSeed()
            ReadinessBootstrap.start()
            PlanBootstrap.start()
            TrainBootstrap.start()
            HealthKitBootstrap.start()
            #if DEBUG
            await SecretsBootstrap.run()
            #endif
            CoachBootstrap.start()
            ChatBootstrap.start()
            BriefBootstrap.start()
            ProactiveBootstrap.start()
            WatchReadinessBootstrap.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private enum DiagnosticsBootstrap {
    static func run() async {
        let logger = helmLogger(category: .ui)
        logger.info("Helm launched")

        await DiagnosticsLog.shared.record(
            category: .ui,
            level: .info,
            message: "Diagnostics bootstrap complete",
            context: ["phase": "M0.3"]
        )

        struct BootstrapTestError: Error {
            let reason: String
        }

        await DiagnosticsLog.shared.capture(
            error: BootstrapTestError(reason: "deliberate M0.3 test error"),
            category: .ui,
            message: "Captured bootstrap test error",
            context: ["source": "M0.3 acceptance"]
        )
    }
}
