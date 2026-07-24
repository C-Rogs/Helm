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
