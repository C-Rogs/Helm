import SwiftUI

public struct HelmRPESlider: View {
    @Binding public var value: Double

    public init(
        value: Binding<Double>,
        range: ClosedRange<Double> = 5 ... 10,
        step: Double = 0.5
    ) {
        _value = value
        _ = range
        _ = step
    }

    public var body: some View {
        HelmRPEWheelPicker(value: $value)
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
