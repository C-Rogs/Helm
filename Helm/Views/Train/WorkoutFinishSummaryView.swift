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
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            header

            statsRow

            SessionTimelineChartView(
                heartRateSamples: summary.heartRateSamples,
                setMarkers: summary.setMarkers,
                exerciseMarkers: summary.exerciseMarkers,
                musicSegments: summary.musicSegments
            )

            if !summary.muscleMovements.isEmpty {
                landmarkSection
            }

            Text(summary.readinessTeaser)
                .helmType(.body, color: HelmColor.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HelmSpacing.md)
        .padding(.vertical, HelmSpacing.sm)
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
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            HelmSectionEyebrow("SESSION COMPLETE")
            Text("Workout logged")
                .helmType(.title)
        }
    }

    private var statsRow: some View {
        HStack(spacing: HelmSpacing.sm) {
            statBlock(label: "SETS", value: "\(summary.setCount)")
            volumeStat
            statBlock(
                label: "LOAD",
                value: String(format: "%.0f", summary.estimatedTRIMP),
                unit: "TRIMP"
            )
            statBlock(label: "TIME", value: "\(summary.durationMinutes)", unit: "min")
        }
    }

    /// Bodyweight / unloaded sessions often log 0 kg; dash reads clearer than a fake zero.
    @ViewBuilder
    private var volumeStat: some View {
        if summary.totalVolumeKilograms > 0.5 {
            statBlock(
                label: "VOLUME",
                value: String(format: "%.0f", summary.totalVolumeKilograms),
                unit: "kg"
            )
        } else {
            statBlock(label: "VOLUME", value: "-")
        }
    }

    private func statBlock(label: String, value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
                HelmNumericText(value)
                    .helmType(.bigNumber)
                if let unit {
                    Text(unit)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var landmarkSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HelmHairlineRule()
            Text("Weekly hard sets")
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

        withAnimation(HelmMotion.animation(HelmMotion.revealAnimation, reduceMotion: reduceMotion)) {
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

#Preview("Workout finish summary songs only") {
    ScrollView {
        WorkoutFinishSummaryView(
            summary: WorkoutFinishSummaryFixtures.songsOnly,
            muscleLabel: { $0.rawValue.capitalized }
        )
    }
    .helmTheme()
}

#Preview("Workout finish summary empty timeline") {
    ScrollView {
        WorkoutFinishSummaryView(
            summary: WorkoutFinishSummaryFixtures.emptyTimeline,
            muscleLabel: { $0.rawValue.capitalized }
        )
    }
    .helmTheme()
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
        readinessTeaser: "Moderate load; readiness should hold steady.",
        heartRateSamples: [
            SessionHeartRateSample(offsetSeconds: 0, bpm: 118),
            SessionHeartRateSample(offsetSeconds: 120, bpm: 142),
            SessionHeartRateSample(offsetSeconds: 240, bpm: 136)
        ],
        setMarkers: [
            SessionSetMarker(offsetSeconds: 120, setNumber: 4),
            SessionSetMarker(offsetSeconds: 240, setNumber: 8)
        ],
        exerciseMarkers: [
            SessionExerciseMarker(offsetSeconds: 60, shortName: "Bench Press"),
            SessionExerciseMarker(offsetSeconds: 300, shortName: "Squat")
        ],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0,
                endOffsetSeconds: 180,
                title: "Lose Yourself",
                artist: "Eminem",
                genre: "Hip-Hop"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 180,
                endOffsetSeconds: 540,
                title: "POWER",
                artist: "Kanye West",
                genre: "Hip-Hop"
            )
        ]
    )

    static let songsOnly = WorkoutFinishSummary(
        setCount: 12,
        totalVolumeKilograms: 0,
        estimatedTRIMP: 189,
        durationMinutes: 7,
        muscleMovements: [],
        readinessTeaser: "Light session; minimal readiness impact.",
        setMarkers: [
            SessionSetMarker(offsetSeconds: 45, setNumber: 1),
            SessionSetMarker(offsetSeconds: 120, setNumber: 4)
        ],
        exerciseMarkers: [
            SessionExerciseMarker(offsetSeconds: 20, shortName: "Chest Dips"),
            SessionExerciseMarker(offsetSeconds: 95, shortName: "Crunches")
        ],
        musicSegments: [
            SessionMusicSegment(
                startOffsetSeconds: 0,
                endOffsetSeconds: 21,
                title: "EASTSIDE",
                artist: "Georges",
                genre: "Electronic"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 21,
                endOffsetSeconds: 236,
                title: "Not Enough",
                artist: "Dam Swindle",
                genre: "Electronic"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 236,
                endOffsetSeconds: 245,
                title: "More Than It Seems",
                artist: "KOLA",
                genre: "Electronic"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 245,
                endOffsetSeconds: 336,
                title: "Two Hearts, Come Through",
                artist: "BowAsWell",
                genre: "Electronic"
            ),
            SessionMusicSegment(
                startOffsetSeconds: 336,
                endOffsetSeconds: 420,
                title: "Encore",
                artist: "Various",
                genre: "Electronic"
            )
        ]
    )

    static let emptyTimeline = WorkoutFinishSummary(
        setCount: 4,
        totalVolumeKilograms: 1_200,
        estimatedTRIMP: 45,
        durationMinutes: 15,
        muscleMovements: [],
        readinessTeaser: "Light session; minimal readiness impact."
    )
}
