import Foundation
import UserNotifications

public enum NotificationAuthorizationStatus: String, Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

protocol NotificationPermissionChecking: Sendable {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension LiveNotificationCenter: NotificationPermissionChecking {
    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .denied
        }
    }
}

@MainActor
final class NotificationPermissionService {
    private let center: any NotificationPermissionChecking

    init(center: any NotificationPermissionChecking = LiveNotificationCenter()) {
        self.center = center
    }

    func currentStatus() async -> NotificationAuthorizationStatus {
        await center.authorizationStatus()
    }

    func requestPermission() async -> NotificationAuthorizationStatus {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await center.authorizationStatus()
    }
}
