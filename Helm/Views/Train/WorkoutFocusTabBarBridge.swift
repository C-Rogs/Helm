import SwiftUI
import UIKit

/// UIKit fallback: SwiftUI `.toolbarVisibility` on `TabView` is unreliable with the
/// iOS 18+ `Tab` API / liquid glass. Drive `UITabBar.isHidden` from the focused tab.
struct WorkoutFocusTabBarBridge: UIViewControllerRepresentable {
    var hideTabBar: Bool

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hideTabBar = hideTabBar
        controller.applyTabBarVisibility()
    }

    final class Controller: UIViewController {
        var hideTabBar = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyTabBarVisibility()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyTabBarVisibility()
        }

        func applyTabBarVisibility() {
            guard let tabBar = nearestTabBar() else { return }
            let shouldHide = hideTabBar
            guard tabBar.isHidden != shouldHide else { return }
            tabBar.isHidden = shouldHide
            // Reclaim layout so Train content can use the freed bottom inset.
            tabBar.superview?.setNeedsLayout()
            tabBar.superview?.layoutIfNeeded()
        }

        private func nearestTabBar() -> UITabBar? {
            var responder: UIResponder? = self
            while let current = responder {
                if let tabController = current as? UITabBarController {
                    return tabController.tabBar
                }
                responder = current.next
            }
            // Walk presented / parent chain from the key window as a backup.
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                for window in scene.windows where window.isKeyWindow {
                    if let tab = window.rootViewController?.helm_tabBarController()?.tabBar {
                        return tab
                    }
                }
            }
            return nil
        }
    }
}

private extension UIViewController {
    func helm_tabBarController() -> UITabBarController? {
        if let tab = self as? UITabBarController { return tab }
        if let tab = tabBarController { return tab }
        for child in children {
            if let tab = child.helm_tabBarController() { return tab }
        }
        return presentedViewController?.helm_tabBarController()
    }
}
