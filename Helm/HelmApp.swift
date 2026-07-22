import Diagnostics
import DesignSystem
import Persistence
import SwiftUI

private let helmNotificationDelegate = HelmNotificationDelegate()

@main
struct HelmApp: App {
    init() {
        HelmFontRegistration.registerFontsIfNeeded()
        Task { @MainActor in
            helmNotificationDelegate.configure()
            await DiagnosticsBootstrap.run()
            await PersistenceBootstrap.logOpen()
            ReadinessBootstrap.start()
            TrainBootstrap.start()
            HealthKitBootstrap.start()
            #if DEBUG
            await SecretsBootstrap.run()
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .helmTheme()
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
