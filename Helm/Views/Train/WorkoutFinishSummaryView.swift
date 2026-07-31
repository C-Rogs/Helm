import Core
import DesignSystem
import HealthKitIngest
import PlanKit
import SwiftUI

struct WorkoutFinishSummaryView: View {
    let summary: WorkoutFinishSummary
    let muscleLabel: (MuscleGroup) -> String

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var animatedMovements: [MuscleGroup: Double] = [:]
    @State private var settled = false

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            header

            statsRow

            SessionHeartRateChartView(
                samples: summary.heartRateSamples,
                markers: summary.setMarkers
            )

            if !summary.muscleMovements.isEmpty {
                landmarkSection
            }

            Text(summary.readinessTeaser)
                .helmType(.body, color: HelmColor.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(HelmSpacing.md)
        .scaleEffect(settled ? 1 : 0.98)
        .opacity(settled ? 1 : 0)
        .onAppear {
            withAnimation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion)) {
                settled = true
            }
            animateLandmarkMovement()
            HapticEngine.shared.play(.sessionFinished)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            HelmSectionEyebrow("SESSION COMPLETE")
            Text("Workout logged")
                .helmType(.title)
        }
    }

    private var statsRow: some View {
        HStack(spacing: HelmSpacing.sm) {
            statBlock(label: "SETS", value: "\(summary.setCount)")
            statBlock(
                label: "VOLUME",
                value: String(format: "%.0f", summary.totalVolumeKilograms),
                unit: "kg"
            )
            statBlock(
                label: "LOAD",
                value: String(format: "%.0f", summary.estimatedTRIMP),
                unit: "TRIMP"
            )
            statBlock(label: "TIME", value: "\(summary.durationMinutes)", unit: "min")
        }
    }

    private func statBlock(label: String, value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
                HelmNumericText(value)
                    .helmType(.number)
                if let unit {
                    Text(unit)
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var landmarkSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HelmHairlineRule()
            Text("Weekly landmarks")
                .helmType(.label)

            ForEach(Array(summary.muscleMovements.enumerated()), id: \.element.id) { index, movement in
                LandmarkVolumeBar(
                    label: muscleLabel(movement.muscle),
                    weeklySets: animatedMovements[movement.muscle] ?? movement.setsBefore,
                    mev: movement.mev,
                    mrv: movement.mrv,
                    state: HelmState.volumeWeekly(
                        sets: animatedMovements[movement.muscle] ?? movement.setsBefore,
                        mev: movement.mev,
                        mrv: movement.mrv
                    )
                )
                .helmStaggeredAppear(index: index + 1)
            }
        }
    }

    private func animateLandmarkMovement() {
        for movement in summary.muscleMovements {
            animatedMovements[movement.muscle] = movement.setsBefore
        }

        guard !reduceMotion else {
            for movement in summary.muscleMovements {
                animatedMovements[movement.muscle] = movement.setsAfter
            }
            return
        }

        withAnimation(HelmMotion.revealAnimation) {
            for movement in summary.muscleMovements {
                animatedMovements[movement.muscle] = movement.setsAfter
            }
        }
    }
}

#Preview("Workout finish summary") {
    ScrollView {
        WorkoutFinishSummaryView(
            summary: WorkoutFinishSummaryFixtures.standard,
            muscleLabel: { $0.rawValue.capitalized }
        )
    }
    .helmTheme()
}

#Preview("Workout finish summary reduce motion") {
    WorkoutFinishSummaryView(
        summary: WorkoutFinishSummaryFixtures.standard,
        muscleLabel: { $0.rawValue.capitalized }
    )
    .helmTheme()
    .environment(\.helmReduceMotion, true)
}

enum WorkoutFinishSummaryFixtures {
    static let standard = WorkoutFinishSummary(
        setCount: 16,
        totalVolumeKilograms: 6_420,
        estimatedTRIMP: 186,
        durationMinutes: 54,
        muscleMovements: [
            MuscleLandmarkDelta(muscle: .chest, setsBefore: 8, setsAfter: 12, mev: 10, mrv: 20),
            MuscleLandmarkDelta(muscle: .quads, setsBefore: 6, setsAfter: 10, mev: 8, mrv: 18),
            MuscleLandmarkDelta(muscle: .back, setsBefore: 14, setsAfter: 16, mev: 10, mrv: 18),
        ],
        readinessTeaser: "Moderate load; readiness should hold steady."
    )
}
