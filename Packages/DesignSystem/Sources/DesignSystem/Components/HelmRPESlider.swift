import SwiftUI

public struct HelmRPESlider: View {
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let step: Double

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 5 ... 10,
        step: Double = 0.5
    ) {
        _value = value
        self.range = range
        self.step = step
    }

    public var body: some View {
        VStack(spacing: HelmSpacing.sm) {
            Text(formattedValue)
                .helmType(.bigNumber)
                .frame(maxWidth: .infinity)

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        value = snapped(newValue)
                        HapticEngine.shared.play(.selection)
                    }
                ),
                in: range,
                step: step
            )
            .tint(HelmColor.accent)
            .padding(.horizontal, HelmSpacing.sm)
        }
        .padding(.vertical, HelmSpacing.sm)
        .background(HelmColor.surface)
    }

    private var formattedValue: String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    private func snapped(_ raw: Double) -> Double {
        let steps = (raw - range.lowerBound) / step
        let rounded = (steps.rounded() * step) + range.lowerBound
        return min(max(rounded, range.lowerBound), range.upperBound)
    }
}

#Preview("RPE slider") {
    struct Harness: View {
        @State private var value = 8.0

        var body: some View {
            HelmRPESlider(value: $value)
                .helmTheme()
        }
    }

    return Harness()
}
