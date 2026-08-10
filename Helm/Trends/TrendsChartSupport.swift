import Charts
import Core
import DesignSystem
import Foundation
import PlanKit
import SwiftUI

enum TrendsChartSupport {
    static func chartDate(for helmDay: HelmDay, calendar: Calendar = .current) -> Date {
        helmDay.startInstant(calendar: calendar)
            ?? calendar.date(from: helmDay.dateComponents())
            ?? .now
    }

    static func shortLabel(for helmDay: HelmDay) -> String {
        String(format: "%02d/%02d", helmDay.month, helmDay.day)
    }

    static func muscleLabel(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .abs: "Abs"
        }
    }

    /// Inclusive start day for a history window ending at `today`.
    static func windowStart(
        for window: TrendsHistoryWindow,
        today: HelmDay,
        calendar: Calendar = .current
    ) -> HelmDay? {
        guard let lookback = window.lookbackDays else { return nil }
        return today.adding(days: -(lookback - 1), calendar: calendar)
    }

    static func windowed<Point>(
        _ points: [Point],
        window: TrendsHistoryWindow,
        today: HelmDay,
        calendar: Calendar = .current,
        day: (Point) -> HelmDay
    ) -> [Point] {
        guard let start = windowStart(for: window, today: today, calendar: calendar) else {
            return points
        }
        return points.filter { day($0) >= start }
    }

    /// Tight Y domain for the plotted series so the line fills the plot.
    /// Optional `nearby` (e.g. target weight) joins the domain only when close enough
    /// that including it won't flatten the trend into a flat band.
    static func autoZoomYDomain(
        values: [Double],
        nearby: Double? = nil,
        minimumSpan: Double = 0.5,
        paddingFraction: Double = 0.15,
        minimumPadding: Double = 0.2,
        nearbySlack: Double = 2.0
    ) -> ClosedRange<Double>? {
        guard let dataMin = values.min(), let dataMax = values.max() else { return nil }

        var low = dataMin
        var high = dataMax
        if let nearby {
            let dataSpan = max(high - low, minimumSpan)
            let slack = max(nearbySlack, dataSpan)
            if nearby >= low - slack, nearby <= high + slack {
                low = min(low, nearby)
                high = max(high, nearby)
            }
        }

        let span = max(high - low, minimumSpan)
        let padding = max(span * paddingFraction, minimumPadding)
        return (low - padding)...(high + padding)
    }

    static func sparklinePoints<Point>(
        from points: [Point],
        last count: Int = 7,
        transform: (Point, Int) -> HelmSparklinePoint
    ) -> [HelmSparklinePoint] {
        Array(points.suffix(count)).enumerated().map { index, point in
            transform(point, index)
        }
    }

    @MainActor
    static func scrubCalloutOverlay(
        proxy: ChartProxy,
        selectedX: Date?,
        label: String?
    ) -> some View {
        GeometryReader { geometry in
            if let selectedX,
               let label,
               let plotFrame = proxy.plotFrame,
               let xPosition = proxy.position(forX: selectedX) {
                let origin = geometry[plotFrame].origin
                let x = origin.x + xPosition

                HelmChartScrubCallout(label: label)
                    .position(x: x, y: origin.y - HelmSpacing.sm)
            }
        }
        .allowsHitTesting(false)
    }
}
