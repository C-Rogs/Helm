import SwiftUI
import UIKit

/// Hard-locks horizontal pan/bounce on a vertical ScrollView. SwiftUI has no `.never` bounce mode.
public final class HelmVerticalScrollLockView: UIView {
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        lock()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        lock()
    }

    private func lock() {
        var ancestor: UIView? = superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                scroll.alwaysBounceHorizontal = false
                scroll.showsHorizontalScrollIndicator = false
                scroll.isDirectionalLockEnabled = true
                scroll.bouncesHorizontally = false
                let inset = scroll.adjustedContentInset
                let maxWidth = max(scroll.bounds.width - inset.left - inset.right, 0)
                if maxWidth > 0, scroll.contentSize.width > maxWidth + 0.5 {
                    scroll.contentSize.width = maxWidth
                }
                if abs(scroll.contentOffset.x + inset.left) > 0.5 {
                    scroll.contentOffset.x = -inset.left
                }
            }
            ancestor = current.superview
        }
    }
}

/// Background lock for page-level vertical ScrollViews (Train, Nutrition diary).
public struct HelmVerticalScrollLock: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> HelmVerticalScrollLockView {
        let view = HelmVerticalScrollLockView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    public func updateUIView(_ uiView: HelmVerticalScrollLockView, context: Context) {
        uiView.setNeedsLayout()
    }
}

public extension View {
    /// Pin scroll content to the viewport width so wide children cannot widen the page.
    func helmVerticalScrollContentWidth(_ width: CGFloat) -> some View {
        frame(width: width, alignment: .leading)
            .clipped()
    }

    /// Apply on the ScrollView itself (not its content).
    func helmVerticalScrollContainer() -> some View {
        scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .contentShape(Rectangle())
            .background(HelmVerticalScrollLock())
    }
}
