import SwiftUI

/// Arc that fills to a normalized progress value, used for backfill and long-running tasks.
public struct ArcProgressGauge<Center: View>: View {
    private let progress: Double
    private let state: HelmState
    private let reduceMotion: Bool
    private let center: Center

    public init(
        progress: Double,
        state: HelmState = .ready,
        reduceMotion: Bool,
        @ViewBuilder center: () -> Center
    ) {
        self.progress = min(max(progress, 0), 1)
        self.state = state
        self.reduceMotion = reduceMotion
        self.center = center()
    }

    public var body: some View {
        ArcGauge(value: progress * 100, range: 0 ... 100, state: state) {
            center
        }
        .arcStateBloom(progress: progress, state: state, reduceMotion: reduceMotion)
        .animation(
            HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: reduceMotion),
            value: progress
        )
    }
}

#if DEBUG
#Preview("Arc progress gauge") {
    ArcProgressGauge(progress: 0.62, reduceMotion: false) {
        VStack(spacing: HelmSpacing.xxs) {
            HelmNumericText(62)
                .helmType(.heroNumber)
            Text("IMPORTING")
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
    }
    .frame(maxWidth: 200)
    .padding()
    .helmTheme()
}
#endif
