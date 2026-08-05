import Charts
import Core
import DesignSystem
import SwiftUI

struct SessionTimelineChartView: View {
    let heartRateSamples: [SessionHeartRateSample]
    let setMarkers: [SessionSetMarker]
    let exerciseMarkers: [SessionExerciseMarker]
    let musicSegments: [SessionMusicSegment]

    private static let heardListLimit = 2
    /// Minimum gap between exercise markers before later labels are dropped.
    private static let minExerciseLabelGapSeconds = 45
    private static let musicLaneOpacity = 0.42
    /// Max chars for in-chart exercise labels (full names live in a11y / session detail).
    private static let exerciseLabelMaxLength = 10
    /// Visible X window before horizontal scroll kicks in (5 minutes).
    private static let visibleWindowSeconds = 5 * 60

    private var hasHeartRate: Bool { !heartRateSamples.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("Session timeline")
                    .helmType(.label)

                if let genreSummary {
                    Text(genreSummary)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                        .lineLimit(1)
                }
            }

            if hasRenderableTimeline {
                chartBody
                if !musicSegments.isEmpty {
                    heardList
                } else {
                    Text(musicEmptyCopy)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
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

    /// BPM (or unit) range for data marks only; excludes label headroom.
    private var dataYDomain: ClosedRange<Double> {
        let bpms = heartRateSamples.map(\.bpm)
        guard let lo = bpms.min(), let hi = bpms.max() else {
            // Unit domain for songs/sets-only: music fills most of the plot.
            return 0...1
        }
        let pad = max(5, (hi - lo) / 8)
        return Double(max(0, lo - pad))...Double(hi + pad)
    }

    /// Share of the data Y domain reserved for the music lane.
    private var musicLaneHeightFraction: Double {
        hasHeartRate ? 0.18 : 0.62
    }

    /// Extra Y headroom (fraction of data span) so exercise labels sit inside the plot.
    private var labelHeadroomFraction: Double {
        hasHeartRate ? 0.28 : 0.45
    }

    /// Plot domain includes top headroom so exercise names render inside the chart frame.
    private var yDomain: ClosedRange<Double> {
        let data = dataYDomain
        let span = max(data.upperBound - data.lowerBound, 1)
        let minHeadroom = hasHeartRate ? 10.0 : 0.55
        let headroom = max(span * labelHeadroomFraction, minHeadroom)
        return data.lowerBound...(data.upperBound + headroom)
    }

    /// Y position for exercise name labels (middle of the headroom band).
    private var exerciseLabelY: Double {
        let data = dataYDomain
        let top = yDomain.upperBound
        return data.upperBound + (top - data.upperBound) * 0.5
    }

    /// Bottom band of the data range reserved for song spans.
    private var musicLane: (start: Double, end: Double) {
        let data = dataYDomain
        let span = data.upperBound - data.lowerBound
        return (data.lowerBound, data.lowerBound + span * musicLaneHeightFraction)
    }

    private var chartHeight: CGFloat {
        if hasHeartRate {
            return HelmChartStyle.standardHeight * 1.65
        }
        // Songs / sets only: thick music lane, no dead BPM grid.
        return HelmChartStyle.standardHeight * 0.85
    }

    private var genreSummary: String? {
        SessionMusicGenreSummary.format(segments: musicSegments)
    }

    private var musicEmptyCopy: String {
        "No songs captured for this session."
    }

    /// Exercise markers keep a label only when far enough from the previously labelled one.
    private var labelledExerciseMarkers: [SessionExerciseMarker] {
        var kept: [SessionExerciseMarker] = []
        var lastLabelledOffset: Int?

        // Scale collision gap with zoom so ~5 min windows stay readable.
        let gap = max(Self.minExerciseLabelGapSeconds, visibleDomainLength / 6)

        for marker in exerciseMarkers.sorted(by: { $0.offsetSeconds < $1.offsetSeconds }) {
            if let last = lastLabelledOffset,
               marker.offsetSeconds - last < gap {
                continue
            }
            kept.append(marker)
            lastLabelledOffset = marker.offsetSeconds
        }

        return kept
    }

    @ViewBuilder
    private var chartBody: some View {
        let lane = musicLane
        let labelY = exerciseLabelY
        let labelled = labelledExerciseMarkers
        let domain = xDomain
        Chart {
            ForEach(heartRateSamples) { sample in
                AreaMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("BPM", Double(sample.bpm))
                )
                .foregroundStyle(HelmChartStyle.areaFill)

                LineMark(
                    x: .value("Time", sample.offsetSeconds),
                    y: .value("BPM", Double(sample.bpm))
                )
                .foregroundStyle(HelmChartStyle.lineColor)
                .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))
                .interpolationMethod(.catmullRom)
            }

            ForEach(musicSegments) { segment in
                RectangleMark(
                    xStart: .value("Song start", segment.startOffsetSeconds),
                    xEnd: .value("Song end", max(segment.endOffsetSeconds, segment.startOffsetSeconds + 1)),
                    yStart: .value("Lane bottom", lane.start),
                    yEnd: .value("Lane top", lane.end)
                )
                .foregroundStyle(HelmColor.accent.opacity(Self.musicLaneOpacity))

                PointMark(
                    x: .value(
                        "Song mark",
                        segment.startOffsetSeconds
                            + max(1, segment.endOffsetSeconds - segment.startOffsetSeconds) / 2
                    ),
                    y: .value("Lane mid", (lane.start + lane.end) / 2)
                )
                .symbol {
                    Image(systemName: "music.note")
                        .font(.system(size: hasHeartRate ? 8 : 10, weight: .bold))
                        .foregroundStyle(HelmColor.accent)
                }
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
            }

            ForEach(labelled) { marker in
                PointMark(
                    x: .value("Exercise label", marker.offsetSeconds),
                    y: .value("Label band", labelY)
                )
                .opacity(0)
                .annotation(
                    position: .overlay,
                    alignment: labelAlignment(for: marker.offsetSeconds, in: domain),
                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
                ) {
                    Text(chartExerciseLabel(marker.shortName))
                        .helmType(.monoTag, color: HelmColor.fgSecondary)
                        .lineLimit(1)
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength)
        .chartPlotStyle { plot in
            plot.padding(HelmChartStyle.plotInsets)
        }
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
        .chartXAxisLabel(position: .bottom, alignment: .trailing) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HelmChartStyle.axisLabelColor)
                .accessibilityLabel("Time")
        }
        .modifier(
            TimelineYAxisModifier(
                hasHeartRate: hasHeartRate,
                dataYDomain: dataYDomain
            )
        )
        .frame(height: chartHeight)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Prefer leading near session start / trailing near end so labels stay in plot.
    private func labelAlignment(for offset: Int, in domain: ClosedRange<Int>) -> Alignment {
        let span = max(domain.upperBound - domain.lowerBound, 1)
        let fraction = Double(offset - domain.lowerBound) / Double(span)
        if fraction < 0.18 { return .leading }
        if fraction > 0.82 { return .trailing }
        return .center
    }

    private func chartExerciseLabel(_ name: String) -> String {
        SessionExerciseMarkerBuilder.truncate(name, maxLength: Self.exerciseLabelMaxLength)
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
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            HStack(spacing: HelmSpacing.xs) {
                Text("Heard")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text("·")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text("\(musicSegments.count)")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }

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
        let timeRange = "\(formatOffset(segment.startOffsetSeconds))-\(formatOffset(segment.endOffsetSeconds))"
        let title = segment.displayTitle
        let artist = segment.displayArtist

        return HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
            Text(timeRange)
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .frame(minWidth: 72, alignment: .leading)
            if let artist {
                Text("\(title) - \(artist)")
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .lineLimit(1)
            } else {
                Text(title)
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .lineLimit(1)
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
            let names = labelledExerciseMarkers.map(\.shortName).joined(separator: ", ")
            if !names.isEmpty {
                parts.append(names)
            }
        }
        return parts.isEmpty ? "Session timeline" : parts.joined(separator: "; ")
    }

    private func formatOffset(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        let rem = clamped % 60
        return String(format: "%d:%02d", minutes, rem)
    }
}

/// Y-axis ticks plus a heart glyph at the axis end when heart rate is present.
private struct TimelineYAxisModifier: ViewModifier {
    let hasHeartRate: Bool
    let dataYDomain: ClosedRange<Double>

    func body(content: Content) -> some View {
        if hasHeartRate {
            content
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(HelmChartStyle.gridColor)
                        AxisValueLabel {
                            if let bpm = value.as(Double.self),
                               bpm <= dataYDomain.upperBound + 0.5 {
                                Text("\(Int(bpm.rounded()))")
                                    .font(HelmChartStyle.axisLabelFont)
                                    .foregroundStyle(HelmChartStyle.axisLabelColor)
                            }
                        }
                    }
                }
                .chartYAxisLabel(position: .trailing, alignment: .top) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HelmChartStyle.axisLabelColor)
                        .accessibilityLabel("Heart rate")
                }
        } else {
            content.chartYAxis(.hidden)
        }
    }
}

#if DEBUG
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
            SessionExerciseMarker(offsetSeconds: 85, shortName: "Incline DB"),
            SessionExerciseMarker(offsetSeconds: 180, shortName: "Squat")
        ],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0,
                endOffsetSeconds: 90,
                title: "Lose Yourself",
                artist: "Eminem",
                genre: "Hip-Hop"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 90,
                endOffsetSeconds: 240,
                title: "POWER",
                artist: "Kanye West",
                genre: "Hip-Hop"
            )
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("Timeline songs only") {
    SessionTimelineChartView(
        heartRateSamples: [],
        setMarkers: [
            SessionSetMarker(offsetSeconds: 45, setNumber: 1),
            SessionSetMarker(offsetSeconds: 120, setNumber: 2)
        ],
        exerciseMarkers: [
            SessionExerciseMarker(offsetSeconds: 20, shortName: "Chest Dips"),
            SessionExerciseMarker(offsetSeconds: 95, shortName: "Crunches"),
            SessionExerciseMarker(offsetSeconds: 180, shortName: "Push-Ups")
        ],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0,
                endOffsetSeconds: 90,
                title: "EASTSIDE",
                artist: "Georges",
                genre: "Electronic"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 90,
                endOffsetSeconds: 240,
                title: "Not Enough",
                artist: "Dam Swindle",
                genre: "Electronic"
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
    let songs = [
        SessionMusicSegment(
            startOffsetSeconds: 0,
            endOffsetSeconds: 900,
            title: "Lose Yourself",
            artist: "Eminem",
            genre: "Hip-Hop"
        ),
        SessionMusicSegment(
            startOffsetSeconds: 900,
            endOffsetSeconds: 2100,
            title: "POWER",
            artist: "Kanye West",
            genre: "Hip-Hop"
        ),
        SessionMusicSegment(
            startOffsetSeconds: 2100,
            endOffsetSeconds: 3600,
            title: "Stronger",
            artist: "Kanye West",
            genre: "Electronic"
        )
    ]
    SessionTimelineChartView(
        heartRateSamples: samples,
        setMarkers: (1...20).map { SessionSetMarker(offsetSeconds: $0 * 180, setNumber: $0) },
        exerciseMarkers: [
            SessionExerciseMarker(offsetSeconds: 300, shortName: "Bench"),
            SessionExerciseMarker(offsetSeconds: 320, shortName: "Close"),
            SessionExerciseMarker(offsetSeconds: 1500, shortName: "Squat"),
            SessionExerciseMarker(offsetSeconds: 2700, shortName: "Row"),
            SessionExerciseMarker(offsetSeconds: 2730, shortName: "Face Pull")
        ],
        musicSegments: songs
    )
    .padding()
    .helmTheme()
}

#Preview("Timeline no songs") {
    SessionTimelineChartView(
        heartRateSamples: [
            SessionHeartRateSample(offsetSeconds: 0, bpm: 100),
            SessionHeartRateSample(offsetSeconds: 75, bpm: 130)
        ],
        setMarkers: [SessionSetMarker(offsetSeconds: 40, setNumber: 1)],
        exerciseMarkers: [
            SessionExerciseMarker(offsetSeconds: 20, shortName: "Iso-Lateral Row"),
            SessionExerciseMarker(offsetSeconds: 55, shortName: "Heavy EZ Bar Curl")
        ],
        musicSegments: []
    )
    .padding()
    .helmTheme()
}
#endif
