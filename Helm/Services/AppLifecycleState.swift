import SwiftUI

/// Tracks whether Helm is foregrounded for notification suppression and lifecycle hooks.
@MainActor
enum AppLifecycleState {
    static private(set) var isForeground = true

    static func update(scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            isForeground = true
        case .inactive, .background:
            isForeground = false
        @unknown default:
            break
        }
    }
}
