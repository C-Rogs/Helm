import SwiftUI

/// Full-page vertical scroll: page moves up/down only.
///
/// Content is pinned to the page width so it cannot grow wider. Horizontal bounce
/// is off when content is not wider than the page (the usual case).
///
/// Nested intentional horizontal strips (week chips, exercise pills) stay their own
/// `ScrollView(.horizontal)`.
public struct HelmVerticalPageScroll<Content: View>: View {
    private let showsIndicators: Bool
    private let content: Content

    public init(
        showsIndicators: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                content
                    .frame(width: geo.size.width, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }
}
