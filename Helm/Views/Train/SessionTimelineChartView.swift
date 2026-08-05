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
    /// Visible X window before horizontal scroll kicks in (5 minutes).
    private static let visibleWindowSeconds = 5 * 60
    /// Half-height of each song bar in BPM units. Wide enough to remain visible
    /// against the heart-rate area while still reading as an exact tempo.
    private static let songBarHalfHeight = 1.75

    @State private var showsAllTracks = false

    @Environment(\.helmReduceMotion) private var reduceMotion

    private var hasHeartRate: Bool { !heartRateSamples.isEmpty }
    private var songBPMSegments: [SessionMusicSegment] {
        musicSegments.filter { $0.bpm != nil }
    }
    /// Tracks with no tempo still get a span in the bottom lane so the timeline never
    /// loses the record of what was playing when.
    private var songSpanSegments: [SessionMusicSegment] {
        musicSegments.filter { $0.bpm == nil }
    }
    private var hasSongBPM: Bool { !songBPMSegments.isEmpty }
    private var hasSongSpans: Bool { !songSpanSegments.isEmpty }
    private var hasBPMScale: Bool { hasHeartRate || hasSongBPM }
    private var tempoLookupEnabled: Bool { SongTempoPreferences.shared.lookupEnabled }

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
                if hasBPMScale || hasSongSpans {
                    seriesLegend
                }
                if let tempoHint {
                    Text(tempoHint)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
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
    /// Marker-only / no-BPM timelines show the full session so the first 5 minutes of
    /// empty lead-in before the first set do not look like a blank chart.
    private var visibleDomainLength: Int {
        let total = max(xDomain.upperBound - xDomain.lowerBound, 1)
        if !hasBPMScale {
            return total
        }
        return min(total, Self.visibleWindowSeconds)
    }

    private var geometry: SessionTimelineChartGeometry {
        SessionTimelineChartGeometry(
            heartRateBPM: heartRateSamples.map { Double($0.bpm) },
            songBPM: songBPMSegments.compactMap(\.bpm),
            hasSongSpans: hasSongSpans
        )
    }

    private var genreSummary: String? {
        SessionMusicGenreSummary.format(segments: musicSegments)
    }

    private var musicEmptyCopy: String {
        "No songs captured for this session."
    }

    /// Explains an empty tempo lane, and points at the switch that can fill it.
    private var tempoHint: String? {
        guard hasSongSpans else { return nil }
        if tempoLookupEnabled {
            return "No tempo found for \(songSpanSegments.count) track(s)."
        }
        return "Tempo lookup off. Turn it on in Settings › Spotify."
    }

    private var seriesLegend: some View {
        HStack(spacing: HelmSpacing.md) {
            if hasHeartRate {
                legendItem(color: HelmChartStyle.lineColor, systemImage: "heart.fill", label: "Heart")
            }
            if hasSongBPM {
                legendItem(color: HelmColor.accent, systemImage: "music.note", label: "Song BPM")
            }
            if hasSongSpans {
                legendItem(
                    color: HelmColor.fgMuted,
                    systemImage: "rectangle.compress.vertical",
                    label: "Song span"
                )
            }
        }
    }

    private func legendItem(color: Color, systemImage: String, label: String) -> some View {
        HStack(spacing: HelmSpacing.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
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
        let layout = geometry
        let labelY = layout.exerciseLabelY
        let songLane = layout.songLaneBand
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
                    y: .value("BPM", Double(sample.bpm)),
                    series: .value("Series", "Heart")
                )
                .foregroundStyle(HelmChartStyle.lineColor)
                .lineStyle(StrokeStyle(lineWidth: HelmChartStyle.lineWidth))
                .interpolationMethod(.catmullRom)
            }

            ForEach(songBPMSegments) { segment in
                if let bpm = segment.bpm {
                    let endX = max(segment.endOffsetSeconds, segment.startOffsetSeconds + 1)
                    RectangleMark(
                        xStart: .value("Song start", segment.startOffsetSeconds),
                        xEnd: .value("Song end", endX),
                        yStart: .value("Song BPM lower", bpm - Self.songBarHalfHeight),
                        yEnd: .value("Song BPM upper", bpm + Self.songBarHalfHeight)
                    )
                    .foregroundStyle(HelmColor.accent)
                    .cornerRadius(2)
                }
            }

            ForEach(Array(songSpanSegments.enumerated()), id: \.element.id) { index, segment in
                let endX = max(segment.endOffsetSeconds, segment.startOffsetSeconds + 1)
                RectangleMark(
                    xStart: .value("Song start", segment.startOffsetSeconds),
                    xEnd: .value("Song end", endX),
                    yStart: .value("Song lane lower", songLane.lowerBound),
                    yEnd: .value("Song lane upper", songLane.upperBound)
                )
                .foregroundStyle(HelmColor.fgMuted.opacity(index.isMultiple(of: 2) ? 0.45 : 0.25))
                .cornerRadius(2)
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
                .symbolSize(1)
                .foregroundStyle(Color.clear)
                .annotation(
                    position: .overlay,
                    alignment: labelAlignment(for: marker.offsetSeconds, in: domain),
                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
                ) {
                    Text(marker.shortName)
                        .helmType(.monoTag, color: HelmColor.fgSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, HelmSpacing.xxs)
                        .padding(.vertical, 2)
                        .background(HelmColor.canvas.opacity(0.88))
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: layout.yDomain)
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
        .modifier(TimelineYAxisModifier(geometry: layout))
        .frame(height: layout.chartHeight)
        .clipped()
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
            Text("Heard")
                .helmType(.monoTag, color: HelmColor.fgMuted)

            ForEach(visibleMusicSegments) { segment in
                heardRow(segment)
            }

            if musicSegments.count > Self.heardListLimit {
                Button {
                    withAnimation(
                        HelmMotion.animation(
                            HelmMotion.quickAnimation,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        showsAllTracks.toggle()
                    }
                } label: {
                    HStack(spacing: HelmSpacing.xxs) {
                        Text(
                            showsAllTracks
                                ? "Show less"
                                : "+\(musicSegments.count - Self.heardListLimit) more"
                        )
                        Image(systemName: showsAllTracks ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .helmType(.monoTag, color: HelmColor.fgSecondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsAllTracks ? "Show fewer tracks" : "Show all tracks")
            }
        }
    }

    private var visibleMusicSegments: [SessionMusicSegment] {
        if showsAllTracks {
            return musicSegments
        }
        return Array(musicSegments.prefix(Self.heardListLimit))
    }

    private func heardRow(_ segment: SessionMusicSegment) -> some View {
        let timeRange = "\(formatOffset(segment.startOffsetSeconds))-\(formatOffset(segment.endOffsetSeconds))"
        let title = segment.displayTitle
        let artist = segment.displayArtist
        let trackLabel: String = {
            if let artist {
                return "\(title) - \(artist)"
            }
            return title
        }()

        return HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
            Text(timeRange)
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .frame(minWidth: 72, alignment: .leading)
            Text(trackLabel)
                .helmType(.body, color: HelmColor.fgSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let bpm = segment.displayBPM {
                Text("\(bpm)")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text("BPM")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            bpmAccessibilityLabel(trackLabel: trackLabel, timeRange: timeRange, bpm: segment.displayBPM)
        )
    }

    private func bpmAccessibilityLabel(trackLabel: String, timeRange: String, bpm: Int?) -> String {
        if let bpm {
            return "\(trackLabel), \(timeRange), \(bpm) BPM"
        }
        return "\(trackLabel), \(timeRange)"
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let first = heartRateSamples.first, let last = heartRateSamples.last {
            parts.append("Heart rate from \(first.bpm) to \(last.bpm) BPM")
        }
        if hasSongBPM {
            let tempos = songBPMSegments.compactMap(\.displayBPM).map(String.init).joined(separator: ", ")
            if tempos.isEmpty {
                parts.append("\(songBPMSegments.count) song tempos")
            } else {
                parts.append("Song tempos \(tempos) BPM")
            }
        }
        if hasSongSpans {
            parts.append("\(songSpanSegments.count) tracks without tempo")
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

/// Y-axis ticks plus a BPM glyph when heart rate or song tempo is present.
private struct TimelineYAxisModifier: ViewModifier {
    let geometry: SessionTimelineChartGeometry

    func body(content: Content) -> some View {
        if geometry.hasBPMScale {
            content
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(HelmChartStyle.gridColor)
                        AxisValueLabel {
                            if let bpm = value.as(Double.self),
                               geometry.showsAxisLabel(at: bpm) {
                                Text("\(Int(bpm.rounded()))")
                                    .font(HelmChartStyle.axisLabelFont)
                                    .foregroundStyle(HelmChartStyle.axisLabelColor)
                            }
                        }
                    }
                }
                .chartYAxisLabel(position: .trailing, alignment: .top) {
                    Text("BPM")
                        .font(HelmChartStyle.axisLabelFont)
                        .foregroundStyle(HelmChartStyle.axisLabelColor)
                        .accessibilityLabel("BPM")
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
            SessionHeartRateSample(offsetSeconds: 90, bpm: 148),
            SessionHeartRateSample(offsetSeconds: 180, bpm: 140)
        ],
        setMarkers: [SessionSetMarker(offsetSeconds: 60, setNumber: 1)],
        exerciseMarkers: [SessionExerciseMarker(offsetSeconds: 60, shortName: "Bench Press")],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0, endOffsetSeconds: 90,
                title: "Lose Yourself", artist: "Eminem", genre: "Hip-Hop", bpm: 171
            ),
            SessionMusicSegment(
                startOffsetSeconds: 90, endOffsetSeconds: 180,
                title: "POWER", artist: "Kanye West", genre: "Hip-Hop", bpm: 154
            )
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("Timeline songs only") {
    SessionTimelineChartView(
        heartRateSamples: [],
        setMarkers: [SessionSetMarker(offsetSeconds: 45, setNumber: 1)],
        exerciseMarkers: [SessionExerciseMarker(offsetSeconds: 20, shortName: "Chest Dips")],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0, endOffsetSeconds: 90,
                title: "EASTSIDE", artist: "Georges", genre: "Electronic", bpm: 124
            ),
            SessionMusicSegment(
                startOffsetSeconds: 90, endOffsetSeconds: 240,
                title: "Not Enough", artist: "Dam Swindle", genre: "Electronic", bpm: 118
            )
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("Timeline mixed BPM") {
    SessionTimelineChartView(
        heartRateSamples: [
            SessionHeartRateSample(offsetSeconds: 0, bpm: 105),
            SessionHeartRateSample(offsetSeconds: 180, bpm: 125)
        ],
        setMarkers: [SessionSetMarker(offsetSeconds: 60, setNumber: 1)],
        exerciseMarkers: [SessionExerciseMarker(offsetSeconds: 30, shortName: "Press")],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0, endOffsetSeconds: 80,
                title: "With Tempo", artist: "Artist", genre: "Rock", bpm: 128
            ),
            SessionMusicSegment(
                startOffsetSeconds: 80, endOffsetSeconds: 180,
                title: "No Tempo", artist: "Spotify Track", genre: "Rock", bpm: nil
            )
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("Timeline long scrollable") {
    let samples = stride(from: 0, through: 3600, by: 60).map { offset in
        SessionHeartRateSample(offsetSeconds: offset, bpm: 120 + (offset / 60) % 40)
    }
    let songs = [
        SessionMusicSegment(
            startOffsetSeconds: 0, endOffsetSeconds: 900,
            title: "Lose Yourself", artist: "Eminem", genre: "Hip-Hop", bpm: 171
        ),
        SessionMusicSegment(
            startOffsetSeconds: 900, endOffsetSeconds: 2100,
            title: "POWER", artist: "Kanye West", genre: "Hip-Hop", bpm: 154
        ),
        SessionMusicSegment(
            startOffsetSeconds: 2100, endOffsetSeconds: 3600,
            title: "Stronger", artist: "Kanye West", genre: "Electronic", bpm: 104
        )
    ]
    SessionTimelineChartView(
        heartRateSamples: samples,
        setMarkers: (1...20).map { SessionSetMarker(offsetSeconds: $0 * 180, setNumber: $0) },
        exerciseMarkers: [
            SessionExerciseMarker(offsetSeconds: 300, shortName: "Bench"),
            SessionExerciseMarker(offsetSeconds: 1500, shortName: "Squat"),
            SessionExerciseMarker(offsetSeconds: 2700, shortName: "Row")
        ],
        musicSegments: songs
    )
    .padding()
    .helmTheme()
}
#endif
