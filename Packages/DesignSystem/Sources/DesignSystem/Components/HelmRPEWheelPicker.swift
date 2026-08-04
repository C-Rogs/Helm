import SwiftUI

public enum HelmRPEWheelValues {
    public static let range: ClosedRange<Double> = 5 ... 10
    public static let step: Double = 0.5

    public static var allValues: [Double] {
        var values: [Double] = []
        var value = range.lowerBound
        while value <= range.upperBound {
            values.append(value)
            value += step
        }
        return values
    }

    public static func snapped(_ raw: Double) -> Double {
        let steps = (raw - range.lowerBound) / step
        let rounded = (steps.rounded() * step) + range.lowerBound
        return min(max(rounded, range.lowerBound), range.upperBound)
    }

    public static func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

public struct HelmRPEWheelPicker: View {
    @Binding public var value: Double

    private let values = HelmRPEWheelValues.allValues
    private let rowHeight = HelmLayout.trainRPEWheelRowHeight

    @State private var scrollPosition: Double?

    public init(value: Binding<Double>) {
        _value = value
    }

    public var body: some View {
        VStack(spacing: HelmSpacing.sm) {
            HelmNumericText(HelmRPEWheelValues.formatted(value))
                .helmType(.bigNumber)
                .frame(maxWidth: .infinity)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(values, id: \.self) { option in
                        wheelRow(for: option)
                            .id(option)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, rowHeight, for: .scrollContent)
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .scrollTargetBehavior(.viewAligned)
            .frame(height: HelmLayout.trainRPEWheelHeight)
            .onChange(of: scrollPosition) { _, newValue in
                guard let newValue else { return }
                let snapped = HelmRPEWheelValues.snapped(newValue)
                guard snapped != value else { return }
                value = snapped
                HapticEngine.shared.play(.selection)
            }
            .onAppear {
                scrollPosition = HelmRPEWheelValues.snapped(value)
            }
            .onChange(of: value) { _, newValue in
                let snapped = HelmRPEWheelValues.snapped(newValue)
                if scrollPosition != snapped {
                    scrollPosition = snapped
                }
            }
        }
        .padding(.vertical, HelmSpacing.sm)
        .background(HelmColor.surface)
    }

    private func wheelRow(for option: Double) -> some View {
        let isSelected = HelmRPEWheelValues.snapped(value) == option

        return Button {
            let snapped = HelmRPEWheelValues.snapped(option)
            guard snapped != value else { return }
            value = snapped
            scrollPosition = snapped
            HapticEngine.shared.play(.selection)
        } label: {
            Text(HelmRPEWheelValues.formatted(option))
                .helmType(
                    isSelected ? .bigNumber : .body,
                    color: isSelected ? HelmColor.accent : HelmColor.fgSecondary
                )
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("RPE \(HelmRPEWheelValues.formatted(option))")
    }
}

#if DEBUG
#Preview("RPE wheel") {
    struct Harness: View {
        @State private var value = 8.0

        var body: some View {
            HelmRPEWheelPicker(value: $value)
                .helmTheme()
        }
    }

    return Harness()
}
#endif
