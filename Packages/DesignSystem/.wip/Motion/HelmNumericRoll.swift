import SwiftUI

/// Engine readout text with mono tabular digits and a numeric roll on value change.
public struct HelmNumericText: View {
    private let text: String

    @Environment(\.helmReduceMotion) private var reduceMotion

    public init(_ text: String) {
        self.text = text
    }

    public init(_ value: Int) {
        self.text = "\(value)"
    }

    public init(_ value: Double, format: String) {
        self.text = String(format: format, value)
    }

    public var body: some View {
        Text(text)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(
                HelmMotion.animation(HelmMotion.quickAnimation, reduceMotion: reduceMotion),
                value: text
            )
    }
}

public extension View {
    /// Applies numeric roll and tokenized animation to numeric engine readouts.
    func helmNumericRoll<Value: Equatable>(value: Value) -> some View {
        modifier(HelmNumericRollModifier(value: value))
    }
}

private struct HelmNumericRollModifier<Value: Equatable>: ViewModifier {
    let value: Value

    @Environment(\.helmReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(
                HelmMotion.animation(HelmMotion.quickAnimation, reduceMotion: reduceMotion),
                value: value
            )
    }
}

#if DEBUG
#Preview("Numeric roll") {
    struct PreviewHarness: View {
        @State private var score = 48

        var body: some View {
            VStack(spacing: HelmSpacing.md) {
                HelmNumericText(score)
                    .helmType(.heroNumber, color: HelmColor.ready)

                Button("Bump score") {
                    score = min(score + 7, 100)
                }
                .buttonStyle(.helmSecondary)
            }
            .padding()
            .helmTheme()
        }
    }

    return PreviewHarness()
}
#endif
