import DesignSystem
import SwiftUI

/// Vertical layout for the session timeline chart.
///
/// Heart rate and song tempo share one BPM scale so they can be read against each other,
/// with a headroom band above for exercise labels and, when some tracks have no tempo,
/// a span lane below the data.
struct SessionTimelineChartGeometry {
    let heartRateBPM: [Double]
    let songBPM: [Double]
    let hasSongSpans: Bool

    var hasBPMScale: Bool { !heartRateBPM.isEmpty || !songBPM.isEmpty }

    /// BPM range for data marks only; excludes label headroom and the song lane.
    var dataYDomain: ClosedRange<Double> {
        let values = heartRateBPM + songBPM
        guard let lowest = values.min(), let highest = values.max() else {
            // Markers / songs without BPM: unit domain for layout only.
            return 0...1
        }
        let pad = max(5.0, (highest - lowest) / 8.0)
        return max(0, lowest - pad)...(highest + pad)
    }

    /// Bottom band reserved for tempo-less song spans, in Y units.
    var songLaneHeight: Double {
        guard hasSongSpans else { return 0 }
        let span = max(dataYDomain.upperBound - dataYDomain.lowerBound, 1)
        return hasBPMScale ? max(span * 0.12, 6) : span * 0.35
    }

    /// Plot domain includes top headroom so exercise names render inside the chart frame.
    var yDomain: ClosedRange<Double> {
        let data = dataYDomain
        let span = max(data.upperBound - data.lowerBound, 1)
        let headroomFraction = hasBPMScale ? 0.28 : 0.45
        let minHeadroom = hasBPMScale ? 10.0 : 0.55
        let headroom = max(span * headroomFraction, minHeadroom)
        return (data.lowerBound - songLaneHeight)...(data.upperBound + headroom)
    }

    /// Vertical band the song-span rectangles occupy, inset from the data area.
    var songLaneBand: ClosedRange<Double> {
        let inset = songLaneHeight * 0.18
        let bottom = dataYDomain.lowerBound - songLaneHeight + inset
        let top = dataYDomain.lowerBound - inset
        return bottom...max(bottom, top)
    }

    /// Y position for exercise name labels (middle of the headroom band).
    var exerciseLabelY: Double {
        let data = dataYDomain
        return data.upperBound + (yDomain.upperBound - data.upperBound) * 0.5
    }

    var chartHeight: CGFloat {
        guard hasBPMScale else { return HelmChartStyle.standardHeight * 1.4 }
        return HelmChartStyle.standardHeight * (hasSongSpans ? 2.4 : 2.2)
    }

    /// True when a Y tick sits inside the data area rather than the label or span bands.
    func showsAxisLabel(at value: Double) -> Bool {
        value >= dataYDomain.lowerBound - 0.5 && value <= dataYDomain.upperBound + 0.5
    }
}
