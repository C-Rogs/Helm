import SwiftUI

@main
struct HelmWatchApp: App {
    @WKApplicationDelegateAdaptor(HelmWatchAppDelegate.self) private var appDelegate

    init() {
        WatchCompanionBootstrap.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
