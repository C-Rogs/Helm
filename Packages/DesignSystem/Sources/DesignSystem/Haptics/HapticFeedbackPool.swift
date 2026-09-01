import UIKit

/// Prepared UIKit generators for same-frame ticks. Creating a generator per fire
/// is the usual first-tap silence / lag.
@MainActor
final class HapticFeedbackPool {
    private let selection = UISelectionFeedbackGenerator()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        selection.prepare()
        light.prepare()
        medium.prepare()
        rigid.prepare()
        soft.prepare()
        notification.prepare()
    }

    func fire(_ fallback: HapticFallback) {
        switch fallback {
        case .selection:
            selection.selectionChanged()
            selection.prepare()
        case let .impact(style):
            let generator = impactGenerator(for: style)
            generator.impactOccurred()
            generator.prepare()
        case let .notification(type):
            notification.notificationOccurred(type)
            notification.prepare()
        }
    }

    private func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: light
        case .medium: medium
        case .heavy: medium
        case .soft: soft
        case .rigid: rigid
        @unknown default: medium
        }
    }
}
