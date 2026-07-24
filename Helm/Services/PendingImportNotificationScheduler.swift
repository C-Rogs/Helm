import Foundation
import UserNotifications

enum PendingImportNotificationScheduler {
    private static let categoryID = "helm.pending-food-import"

    static func postResolved(count: Int) async {
        guard count > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = count == 1 ? "Food import updated" : "\(count) food imports updated"
        content.body = "Offline barcode scans were matched to branded products."
        content.sound = .default
        content.categoryIdentifier = categoryID

        let request = UNNotificationRequest(
            identifier: "helm.pending-food-import.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        _ = try? await UNUserNotificationCenter.current().add(request)
    }
}
