import SwiftUI

public enum HelmDurationWheelValues {
    public static let minSeconds = 15
    public static let maxSeconds = 600
    public static let stepSeconds = 5
    public static let defaultSeconds = 90
    public static let presets = [60, 90, 120, 180]

    public static var allValues: [Int] {
        Array(stride(from: minSeconds, through: maxSeconds, by: stepSeconds))
    }

    public static func snapped(_ raw: Int) -> Int {
        let clamped = min(max(raw, minSeconds), maxSeconds)
        let offset = clamped - minSeconds
        let steps = Int((Double(offset) / Double(stepSeconds)).rounded())
        return min(max(minSeconds + steps * stepSeconds, minSeconds), maxSeconds)
    }

    public static func formatted(_ seconds: Int) -> String {
        RestTimerFormatting.mmss(seconds)
    }

    public static func isPreset(_ seconds: Int) -> Bool {
        presets.contains(seconds)
    }
}

public struct HelmDurationWheelPicker: View {
    @Binding public var value: Int

    private let values = HelmDurationWheelValues.allValues
    private let rowHeight = HelmLayout.trainRPEWheelRowHeight

    @State private var scrollPosition: Int?

    public init(value: Binding<Int>) {
        _value = value
    }

    public var body: some View {
        VStack(spacing: HelmSpacing.sm) {
            HelmNumericText(HelmDurationWheelValues.formatted(value))
                .helmType(.bigNumber)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Duration \(HelmDurationWheelValues.formatted(value))")

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
                let snapped = HelmDurationWheelValues.snapped(newValue)
                guard snapped != value else { return }
                value = snapped
                HapticEngine.shared.play(.selection)
            }
            .onAppear {
                scrollPosition = HelmDurationWheelValues.snapped(value)
            }
            .onChange(of: value) { _, newValue in
                let snapped = HelmDurationWheelValues.snapped(newValue)
                if scrollPosition != snapped {
                    scrollPosition = snapped
                }
            }
        }
        .padding(.vertical, HelmSpacing.sm)
        .background(HelmColor.surface)
    }

    private func wheelRow(for option: Int) -> some View {
        let isSelected = HelmDurationWheelValues.snapped(value) == option

        return Button {
            let snapped = HelmDurationWheelValues.snapped(option)
            guard snapped != value else { return }
            value = snapped
            scrollPosition = snapped
            HapticEngine.shared.play(.selection)
        } label: {
            Text(HelmDurationWheelValues.formatted(option))
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
        .accessibilityLabel("Duration \(HelmDurationWheelValues.formatted(option))")
    }
}

#if DEBUG
#Preview("Duration wheel") {
    struct Harness: View {
        @State private var value = 90

        var body: some View {
            HelmDurationWheelPicker(value: $value)
                .helmTheme()
        }
    }

    return Harness()
}
#endif
