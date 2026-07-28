import SwiftUI

/// Plots a value inside its personal reference range, the transparency-theme atom.
public struct DeviationBand: View {
    public enum Layout: Sendable {
        /// Contributor row: label, value, band track, optional range caption.
        case bar
        /// Compact single-line band for tight surfaces.
        case inline
    }

    private let label: String?
    private let value: Double
    private let band: ClosedRange<Double>?
    private let unit: String
    private let state: HelmState
    private let verdictTag: String?
    private let layout: Layout
    private let decimalPlaces: Int
    private let isValueAvailable: Bool

    public init(
        label: String? = nil,
        value: Double,
        band: ClosedRange<Double>?,
        unit: String,
        state: HelmState,
        verdictTag: String? = nil,
        layout: Layout = .bar,
        decimalPlaces: Int = 1,
        isValueAvailable: Bool = true
    ) {
        self.label = label
        self.value = value
        self.band = band
        self.unit = unit
        self.state = state
        self.verdictTag = verdictTag
        self.layout = layout
        self.decimalPlaces = decimalPlaces
        self.isValueAvailable = isValueAvailable
    }

    public var body: some View {
        switch layout {
        case .bar:
            barLayout
        case .inline:
            inlineLayout
        }
    }

    private var barLayout: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            headerRow

            valueRow

            if band != nil {
                bandTrack
                bandCaption
            } else {
                coldStartCaption
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var inlineLayout: some View {
        HStack(alignment: .center, spacing: HelmSpacing.sm) {
            if let label {
                Text(label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .frame(minWidth: HelmSpacing.xl * 2, alignment: .leading)
            }

            if band != nil {
                bandTrack
                    .frame(maxWidth: .infinity)
            } else {
                Text("Building baseline")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            valueRow
                .layoutPriority(1)

            if let verdictTag {
                verdictTagView(verdictTag)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            if let label {
                Text(label)
                    .helmType(.label)
            }

            Spacer(minLength: HelmSpacing.sm)

            if let verdictTag {
                verdictTagView(verdictTag)
            }
        }
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
            Text(formattedValue)
                .helmType(.number, color: isValueAvailable ? HelmColor.color(for: state) : HelmColor.fgMuted)

            if isValueAvailable {
                Text(unit)
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
    }

    private var bandTrack: some View {
        GeometryReader { geometry in
            let metrics = trackMetrics(width: geometry.size.width)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(HelmColor.hairline)

                if let metrics {
                    Capsule()
                        .fill(HelmColor.color(for: state).opacity(0.22))
                        .frame(width: metrics.bandWidth)
                        .offset(x: metrics.bandOffset)

                    Circle()
                        .fill(HelmColor.color(for: state))
                        .frame(width: HelmSpacing.xs, height: HelmSpacing.xs)
                        .offset(x: metrics.markerOffset)
                }
            }
        }
        .frame(height: HelmLayout.progressTrackHeight)
    }

    @ViewBuilder
    private var bandCaption: some View {
        if let band {
            Text("\(format(band.lowerBound))-\(format(band.upperBound)) \(unit)")
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
    }

    private var coldStartCaption: some View {
        Text("Building baseline")
            .helmType(.monoTag, color: HelmColor.fgMuted)
    }

    private func verdictTagView(_ tag: String) -> some View {
        Text(tag.uppercased())
            .helmType(.monoTag, color: HelmColor.color(for: state))
            .padding(.horizontal, HelmSpacing.xs)
            .padding(.vertical, HelmSpacing.xxs)
            .background(HelmColor.color(for: state).opacity(0.15), in: Capsule())
    }

    private var formattedValue: String {
        isValueAvailable ? format(value) : "--"
    }

    private func format(_ number: Double) -> String {
        String(format: "%.\(decimalPlaces)f", number)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let label { parts.append(label) }
        parts.append("\(formattedValue) \(unit)")
        if let band {
            parts.append("band \(format(band.lowerBound)) to \(format(band.upperBound))")
        } else {
            parts.append("baseline building")
        }
        if let verdictTag { parts.append(verdictTag) }
        parts.append(state.label)
        return parts.joined(separator: ", ")
    }

    private struct TrackMetrics {
        let bandOffset: CGFloat
        let bandWidth: CGFloat
        let markerOffset: CGFloat
    }

    private func trackMetrics(width: CGFloat) -> TrackMetrics? {
        guard let band, width > 0 else { return nil }

        let display = displayRange(band: band, value: value)
        let span = display.upperBound - display.lowerBound
        guard span > 0 else { return nil }

        let markerDiameter = HelmSpacing.xs
        let usable = max(width - markerDiameter, 0)

        let bandStart = (band.lowerBound - display.lowerBound) / span
        let bandEnd = (band.upperBound - display.lowerBound) / span
        let markerCenter = (value - display.lowerBound) / span

        let bandOffset = CGFloat(bandStart) * usable
        let bandWidth = max(CGFloat(bandEnd - bandStart) * usable, HelmSpacing.xxs)
        let markerOffset = min(max(CGFloat(markerCenter) * usable, 0), usable)

        return TrackMetrics(
            bandOffset: bandOffset,
            bandWidth: bandWidth,
            markerOffset: markerOffset
        )
    }

    private func displayRange(
        band: ClosedRange<Double>,
        value: Double
    ) -> ClosedRange<Double> {
        let span = band.upperBound - band.lowerBound
        let padding = max(span * 0.15, 0.5)
        let lower = min(band.lowerBound - padding, value - padding * 0.5)
        let upper = max(band.upperBound + padding, value + padding * 0.5)
        guard upper > lower else { return band }
        return lower ... upper
    }
}

#if DEBUG
private struct DeviationBandPreviewMatrix: View {
    let palette: HelmPalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                previewGroup("In band") {
                    DeviationBand(
                        label: "HRV",
                        value: 45.3,
                        band: 44.3 ... 49.3,
                        unit: "ms",
                        state: .ready,
                        verdictTag: "GOOD"
                    )
                }

                previewGroup("Below band") {
                    DeviationBand(
                        label: "HRV",
                        value: 41.2,
                        band: 44.3 ... 49.3,
                        unit: "ms",
                        state: .depleted,
                        verdictTag: "LOW"
                    )
                }

                previewGroup("Above band") {
                    DeviationBand(
                        label: "Resting HR",
                        value: 58,
                        band: 48 ... 54,
                        unit: "bpm",
                        state: .compromised,
                        verdictTag: "HIGH",
                        decimalPlaces: 0
                    )
                }

                previewGroup("Cold start") {
                    DeviationBand(
                        label: "Sleep",
                        value: 7.1,
                        band: nil,
                        unit: "h",
                        state: .compromised,
                        verdictTag: "PROVISIONAL"
                    )
                }

                previewGroup("Inline") {
                    VStack(spacing: HelmSpacing.sm) {
                        DeviationBand(
                            label: "HRV",
                            value: 45.3,
                            band: 44.3 ... 49.3,
                            unit: "ms",
                            state: .ready,
                            verdictTag: "GOOD",
                            layout: .inline
                        )
                        DeviationBand(
                            label: "Sleep",
                            value: 6.4,
                            band: nil,
                            unit: "h",
                            state: .compromised,
                            layout: .inline
                        )
                    }
                }
            }
            .padding(HelmSpacing.screenGutter)
        }
        .helmTheme()
        .environment(\.helmPalette, palette)
        .environment(\.helmSkin, .instrument)
    }

    private func previewGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text(title)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            content()
        }
    }
}

#Preview("DeviationBand dark") {
    DeviationBandPreviewMatrix(palette: .dark)
        .preferredColorScheme(.dark)
}

#Preview("DeviationBand light") {
    DeviationBandPreviewMatrix(palette: .light)
        .preferredColorScheme(.light)
}

#Preview("DeviationBand accessibility") {
    DeviationBandPreviewMatrix(palette: .dark)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
#endif
