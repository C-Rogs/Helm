import Foundation

/// Watch rest Skip / ±15. Phone `AppRootView` applies via `TrainSessionController`.
enum WatchRestControlBridge {
    static let notificationName = Notification.Name("com.cameronro.helm.watch.restControl")
    static let actionKey = "action"
    static let skipAction = "skip"
    static let adjustAction = "adjust"
    static let deltaKey = "deltaSeconds"
}
