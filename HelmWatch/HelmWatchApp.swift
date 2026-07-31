import SwiftUI

@main
struct HelmWatchApp: App {
    @WKApplicationDelegateAdaptor(HelmWatchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
