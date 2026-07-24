import Charts
import SwiftUI

public struct HelmChartScrubCallout: View {
    private let label: String

    public init(label: String) {
        self.label = label
    }

    public var body: some View {
        Text(label)
            .helmType(.number)
            .padding(.horizontal, HelmSpacing.xs)
            .padding(.vertical, HelmSpacing.xxs)
            .background(HelmColor.surfaceElevated, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(HelmColor.hairline, lineWidth: 1)
            }
    }
}

private struct HelmChartScrubModifier<X: Plottable & Hashable>: ViewModifier {
    @Binding var selection: X?
    let onSelectionChange: ((X?) -> Void)?

    @State private var lastHapticSelection: X?
    @Environment(\.helmReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $selection)
            .onChange(of: selection) { _, newValue in
                onSelectionChange?(newValue)
                guard let newValue, newValue != lastHapticSelection else { return }
                lastHapticSelection = newValue
                HapticEngine.shared.play(.selection)
            }
            .animation(
                HelmMotion.animation(HelmMotion.quickAnimation, reduceMotion: reduceMotion),
                value: selection
            )
    }
}

public extension View {
    func helmChartScrub<X: Plottable & Hashable>(
        selection: Binding<X?>,
        onSelectionChange: ((X?) -> Void)? = nil
    ) -> some View {
        modifier(
            HelmChartScrubModifier(
                selection: selection,
                onSelectionChange: onSelectionChange
            )
        )
    }
}

#if DEBUG
#Preview("Scrub callout") {
    HelmChartScrubCallout(label: "72")
        .padding()
        .helmTheme()
}
#endif
