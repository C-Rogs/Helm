import SwiftUI

public struct Gauge: View {
    private let value: Double
    private let label: String?
    private let subtitle: String?

    public init(value: Double, label: String? = nil, subtitle: String? = nil) {
        self.value = min(max(value, 0), 100)
        self.label = label
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: HelmSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(HelmColor.gaugeTrack, lineWidth: 10)

                Circle()
                    .trim(from: 0, to: value / 100)
                    .stroke(
                        AngularGradient(
                            colors: [HelmColor.gaugeFillStart, HelmColor.gaugeFillEnd],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: HelmSpacing.xxs) {
                    Text("\(Int(value.rounded()))")
                        .helmType(.heroNumber, color: HelmColor.textPrimary)
                        .monospacedDigit()
                    if let label {
                        Text(label)
                            .helmType(.body, color: HelmColor.textSecondary)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(HelmSpacing.sm)

            if let subtitle {
                Text(subtitle)
                    .helmType(.body, color: HelmColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview("Gauge") {
    Gauge(value: 72, label: "ARC", subtitle: "Full baseline")
        .padding()
        .frame(width: 220)
        .helmTheme()
}
