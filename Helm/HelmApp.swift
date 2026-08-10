import Diagnostics
import DesignSystem
import Persistence
import SwiftUI

@main
struct HelmApp: App {
    @UIApplicationDelegateAdaptor(HelmAppDelegate.self) private var appDelegate

    init() {
        if ProcessInfo.processInfo.arguments.contains("-helm-uitesting") {
            UserDefaults.standard.set(true, forKey: OnboardingStore.completedDefaultsKey)
        }
        HelmFontRegistration.registerFontsIfNeeded()
        Task { @MainActor in
            await DiagnosticsBootstrap.run()
            await PersistenceBootstrap.logOpen()
            // Hydrate ARC before seed/iCloud so dashboard is not blocked on those.
            ReadinessBootstrap.start()
            await PersistenceBootstrap.importExerciseSeed()
            if !ProcessInfo.processInfo.arguments.contains("-helm-uitesting") {
                try? CoachMemoryAdjuster.seedShoulderNiggleIfNeeded(
                    persistence: PersistenceBootstrap.persistenceStore
                )
            }
            await CloudBackupCoordinator.shared.pullIfNeededOnLaunch()
            PlanBootstrap.start()
            TrainBootstrap.start()
            HealthKitBootstrap.start()
            #if DEBUG
            await SecretsBootstrap.run()
            #endif
            CoachArchetypeBootstrap.start()
            CoachBootstrap.start()
            ChatBootstrap.start()
            BriefBootstrap.start()
            NutritionBootstrap.start()
            TrendsBootstrap.start()
            MethodologyBootstrap.start()
            ProactiveBootstrap.start()
            WatchReadinessBootstrap.start()
            // Prepare bell buffer only - do not activate AVAudioSession (pauses music).
            RestTimerSoundPlayer.shared.prewarmSession()
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
