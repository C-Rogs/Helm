import Charts
import Core
import DesignSystem
import SwiftUI

struct SessionTimelineChartView: View {
    let heartRateSamples: [SessionHeartRateSample]
    let setMarkers: [SessionSetMarker]
    let exerciseMarkers: [SessionExerciseMarker]
    let musicSegments: [SessionMusicSegment]

    private static let heardListLimit = 8
    private static let songAnnotationMaxLength = 14
    private static let minLabelSpanSeconds = 45
    /// Visible X window before horizontal scroll kicks in (~12 minutes).
    private static let visibleWindowSeconds = 12 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Session timeline")
                .helmType(.label)

            if hasRenderableTimeline {
                chartBody
                if !musicSegments.isEmpty {
                    heardList
                }
            } else {
                Text("No heart rate or music recorded for this session.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .frame(maxWidth: .infinity, minHeight: HelmLayout.emptyChartMinHeight, alignment: .leading)
            }
        }
    }

    private var hasRenderableTimeline: Bool {
        !heartRateSamples.isEmpty || !setMarkers.isEmpty || !exerciseMarkers.isEmpty || !musicSegments.isEmpty
    }

    /// Inclusive session-relative domain. Always starts at 0 so Charts cannot invent negative time.
    private var xDomain: ClosedRange<Int> {
        var maxOffset = 0
        for sample in heartRateSamples {
            maxOffset = max(maxOffset, sample.offsetSeconds)
        }
        for marker in setMarkers {
            maxOffset = max(maxOffset, marker.offsetSeconds)
        }
        for marker in exerciseMarkers {
            maxOffset = max(maxOffset, marker.offsetSeconds)
        }
        for segment in musicSegments {
            maxOffset = max(maxOffset, segment.endOffsetSeconds, segment.startOffsetSeconds)
        }
        return 0...max(maxOffset, 1)
    }

    /// Seconds shown on screen at once. Shorter sessions fill width; longer ones scroll.
    private var visibleDomainLength: Int {
        let total = max(xDomain.upperBound - xDomain.lowerBound, 1)
        return min(total, Self.visibleWindowSeconds)
    }

    private var bpmRange: (min: Int, max: Int) {
        let bpms = heartRateSamples.map(\.bpm)
        guard let lo = bpms.min(), let hi = bpms.max() else {
            return (0, 1)
        }
        let pad = max(5, (hi - lo) / 8)
        return (max(0, lo - pad), hi + pad)
    }

    @ViewBuilder
    private var chartBody: some View {
        let bpm = bpmRange
        Chart {
            ForEach(musicSegments) { segment in
                RectangleMark(
                    xStart: .value("Song start", segment.startOffsetSeconds),
                    xEnd: .value("Song end", max(segment.endOffsetSeconds, segment.startOffsetSeconds + 1)),
                    yStart: .value("BPM low", bpm.min),
                    yEnd: .value("BPM high", bpm.max)
                )
                .foregroundStyle(HelmColor.accent.opacity(0.14))

                if shouldLabelSong(segment) {
                    PointMark(
                        x: .value("Song label", songLabelX(segment)),
                        y: .value("BPM", bpm.min)
                    )
                    .opacity(0)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(truncatedSongLabel(segment))
                            .helmType(.monoTag, color: HelmColor.accent)
                            .lineLimit(1)
                    }
                }
            }

            ForEach(heartRateSamples) { sample in
                AreaMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(HelmChartStyle.areaFill)

                LineMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("BPM", sample.bpm)
                )
                .foregroundStyle(HelmChartStyle.lineColor)
                .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))
                .interpolationMethod(.catmullRom)
            }

            ForEach(setMarkers) { marker in
                RuleMark(x: .value("Set", marker.offsetSeconds))
                    .foregroundStyle(HelmColor.fgMuted.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            ForEach(exerciseMarkers) { marker in
                RuleMark(x: .value("Exercise", marker.offsetSeconds))
                    .foregroundStyle(HelmColor.fgSecondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .annotation(position: .top, alignment: .center) {
                        Text(marker.shortName)
                            .helmType(.monoTag, color: HelmColor.fgSecondary)
                    }
            }
        }
        .helmChartStyle()
        .chartXScale(domain: xDomain)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength)
        .chartXAxis {
            AxisMarks(values: .stride(by: Double(axisStrideSeconds))) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(HelmChartStyle.gridColor)
                AxisValueLabel {
                    if let seconds = value.as(Int.self) ?? value.as(Double.self).map(Int.init) {
                        Text(formatOffset(seconds))
                            .helmFont(.monoTag)
                            .foregroundStyle(HelmChartStyle.axisLabelColor)
                    }
                }
            }
        }
        .chartYAxis(heartRateSamples.isEmpty ? .hidden : .automatic)
        .modifier(TimelineYScaleModifier(hasHeartRate: !heartRateSamples.isEmpty, bpmRange: bpm))
        .frame(height: HelmChartStyle.standardHeight)
        .accessibilityLabel(accessibilityLabel)
    }

    /// ~4 ticks in the visible window; snap to whole minutes when window is long enough.
    private var axisStrideSeconds: Int {
        let raw = max(visibleDomainLength / 4, 30)
        if visibleDomainLength >= 240 {
            return max((raw / 60) * 60, 60)
        }
        return raw
    }

    private var heardList: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Heard")
                .helmType(.monoTag, color: HelmColor.fgMuted)

            ForEach(Array(musicSegments.prefix(Self.heardListLimit))) { segment in
                heardRow(segment)
            }

            if musicSegments.count > Self.heardListLimit {
                Text("+\(musicSegments.count - Self.heardListLimit) more")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
    }

    private func heardRow(_ segment: SessionMusicSegment) -> some View {
        let timeRange = "\(formatOffset(segment.startOffsetSeconds))–\(formatOffset(segment.endOffsetSeconds))"
        let title = segment.displayTitle
        let artist = segment.displayArtist

        return HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
            Text(timeRange)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            Text("·")
                .helmType(.monoTag, color: HelmColor.fgMuted)
            if let artist {
                Text("\(title) - \(artist)")
                    .helmType(.body, color: HelmColor.fgSecondary)
            } else {
                Text(title)
                    .helmType(.body, color: HelmColor.fgSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let first = heartRateSamples.first, let last = heartRateSamples.last {
            parts.append("Heart rate from \(first.bpm) to \(last.bpm) BPM")
        }
        if !musicSegments.isEmpty {
            parts.append("\(musicSegments.count) tracks")
        }
        if !exerciseMarkers.isEmpty {
            parts.append("\(exerciseMarkers.count) exercises")
        }
        return parts.isEmpty ? "Session timeline" : parts.joined(separator: "; ")
    }

    private func shouldLabelSong(_ segment: SessionMusicSegment) -> Bool {
        (segment.endOffsetSeconds - segment.startOffsetSeconds) >= Self.minLabelSpanSeconds
    }

    private func songLabelX(_ segment: SessionMusicSegment) -> Int {
        let mid = segment.startOffsetSeconds + (segment.endOffsetSeconds - segment.startOffsetSeconds) / 2
        return min(max(mid, xDomain.lowerBound), xDomain.upperBound)
    }

    private func truncatedSongLabel(_ segment: SessionMusicSegment) -> String {
        SessionExerciseMarkerBuilder.truncate(
            segment.displayTitle,
            maxLength: Self.songAnnotationMaxLength
        )
    }

    private func formatOffset(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let rem = clamped % 60
        return String(format: "%d:%02d", minutes, rem)
    }
}

private struct TimelineYScaleModifier: ViewModifier {
    let hasHeartRate: Bool
    let bpmRange: (min: Int, max: Int)

    func body(content: Content) -> some View {
        if hasHeartRate {
            content.chartYScale(domain: bpmRange.min...bpmRange.max)
        } else {
            content.chartYScale(domain: 0...1)
        }
    }
}

#Preview("Timeline HR + songs") {
    SessionTimelineChartView(
        heartRateSamples: [
            SessionHeartRateSample(offsetSeconds: 0, bpm: 110),
            SessionHeartRateSample(offsetSeconds: 60, bpm: 132),
            SessionHeartRateSample(offsetSeconds: 120, bpm: 148),
            SessionHeartRateSample(offsetSeconds: 180, bpm: 140)
        ],
        setMarkers: [
            SessionSetMarker(offsetSeconds: 60, setNumber: 1),
            SessionSetMarker(offsetSeconds: 180, setNumber: 2)
        ],
        exerciseMarkers: [
            SessionExerciseMarker(offsetSeconds: 60, shortName: "Bench Press"),
            SessionExerciseMarker(offsetSeconds: 180, shortName: "Squat")
        ],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0,
                endOffsetSeconds: 90,
                title: "Lose Yourself",
                artist: "Eminem"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 90,
                endOffsetSeconds: 240,
                title: "POWER",
                artist: "Kanye West"
            )
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("Timeline songs only") {
    SessionTimelineChartView(
        heartRateSamples: [],
        setMarkers: [SessionSetMarker(offsetSeconds: 120, setNumber: 1)],
        exerciseMarkers: [],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0,
                endOffsetSeconds: 180,
                title: "Eye of the Tiger",
                artist: "Survivor"
            )
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("Timeline long scrollable") {
    let samples = stride(from: 0, through: 3600, by: 60).map { offset in
        SessionHeartRateSample(
            offsetSeconds: offset,
            bpm: 120 + (offset / 60) % 40
        )
    }
    SessionTimelineChartView(
        heartRateSamples: samples,
        setMarkers: [
            SessionSetMarker(offsetSeconds: 600, setNumber: 4),
            SessionSetMarker(offsetSeconds: 1800, setNumber: 12),
            SessionSetMarker(offsetSeconds: 3000, setNumber: 20)
        ],
        exerciseMarkers: [
            SessionExerciseMarker(offsetSeconds: 300, shortName: "Bench"),
            SessionExerciseMarker(offsetSeconds: 1500, shortName: "Squat"),
            SessionExerciseMarker(offsetSeconds: 2700, shortName: "Row")
        ],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0,
                endOffsetSeconds: 900,
                title: "Lose Yourself",
                artist: "Eminem"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 900,
                endOffsetSeconds: 2100,
                title: "POWER",
                artist: "Kanye West"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 2100,
                endOffsetSeconds: 3600,
                title: "Stronger",
                artist: "Kanye West"
            )
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("Timeline empty") {
    SessionTimelineChartView(
        heartRateSamples: [],
        setMarkers: [],
        exerciseMarkers: [],
        musicSegments: []
    )
    .padding()
    .helmTheme()
}
