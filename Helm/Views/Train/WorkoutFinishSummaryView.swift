import CoachLLM
import Core
import DesignSystem
import HealthKitIngest
import PlanKit
import SwiftUI

struct WorkoutFinishSummaryView: View {
    let summary: WorkoutFinishSummary
    let muscleLabel: (MuscleGroup) -> String
    var eyebrow: String = "SESSION COMPLETE"
    var title: String = "Workout logged"
    var playsCompletionHaptic: Bool = true
    /// Zero when the host screen already applies its own gutter.
    var horizontalPadding: CGFloat = HelmSpacing.md
    /// Finish sheet fades/scales in; history detail should paint immediately.
    var animatesEntrance: Bool = true

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

            if let complianceCard = summary.complianceCard {
                complianceSection(complianceCard)
            }

            Text(summary.readinessTeaser)
                .helmType(.body, color: HelmColor.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, HelmSpacing.sm)
        .scaleEffect(animatesEntrance ? (settled ? 1 : 0.98) : 1)
        .opacity(animatesEntrance ? (settled ? 1 : 0) : 1)
        .onAppear {
            if animatesEntrance {
                withAnimation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion)) {
                    settled = true
                }
            } else {
                settled = true
            }
            animateLandmarkMovement()
            if playsCompletionHaptic {
                HapticEngine.shared.play(.sessionFinished)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            HelmSectionEyebrow(eyebrow)
            Text(title)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let unit {
                    Text(unit)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                        .lineLimit(1)
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
                .modifier(LandmarkAppearModifier(index: index + 1, enabled: animatesEntrance))
            }
        }
    }

    // MARK: - Plan Compliance

    private func complianceSection(_ card: SessionOutcomeCard) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HelmHairlineRule()
            HelmSectionEyebrow("PLAN COMPLIANCE")

            ForEach(card.exercises, id: \.name) { exercise in
                complianceRow(exercise)
            }

            HStack(spacing: HelmSpacing.xxs) {
                Text("Overall match")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text("\(matchPercentage(for: card))%")
                    .helmType(.bigNumber)
            }
        }
    }

    private func complianceRow(_ exercise: SessionOutcomeCard.ExerciseOutcome) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.sm) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(exercise.name)
                    .helmType(.label)
                HStack(spacing: HelmSpacing.sm) {
                    Text("\(exercise.completedSets)/\(exercise.prescribedSets) sets")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                    if let rx = exercise.prescribedKg, let actual = exercise.actualKg {
                        let diff = actual - rx
                        if abs(diff) > 0.5 {
                            Text("\(String(format: "%.0f", actual)) vs \(String(format: "%.0f", rx)) kg")
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                        } else {
                            Text("\(String(format: "%.0f", actual)) kg (on plan)")
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            deviationBadge(exercise.deviations)
        }
    }

    private func deviationBadge(_ deviations: [SessionOutcomeCard.ExerciseOutcome.Deviation]) -> some View {
        HStack(spacing: HelmSpacing.xxs) {
            ForEach(uniqueVisibleDeviations(from: deviations), id: \.self) { dev in
                Text(dev.displayLabel)
                    .helmType(.monoTag, color: deviationColor(dev))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(deviationColor(dev).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func uniqueVisibleDeviations(from deviations: [SessionOutcomeCard.ExerciseOutcome.Deviation]) -> [SessionOutcomeCard.ExerciseOutcome.Deviation] {
        let filtered = deviations.filter { $0 != .matched }
        let seen = Array(NSOrderedSet(array: filtered)) as? [SessionOutcomeCard.ExerciseOutcome.Deviation] ?? filtered
        return seen.isEmpty ? [.matched] : seen
    }

    private func deviationColor(_ dev: SessionOutcomeCard.ExerciseOutcome.Deviation) -> Color {
        switch dev {
        case .matched, .loadExceeded, .volumeExtra: return HelmColor.ready
        case .loadDropped, .volumeSkipped, .exerciseSkipped: return HelmColor.warning
        case .exerciseAdded: return HelmColor.fgMuted
        }
    }

    private func matchPercentage(for card: SessionOutcomeCard) -> Int {
        guard !card.exercises.isEmpty else { return 100 }
        let matched = card.exercises.filter { ex in
            let negatives: Set<SessionOutcomeCard.ExerciseOutcome.Deviation> = [
                .loadDropped, .volumeSkipped, .exerciseSkipped
            ]
            return Set(ex.deviations).isDisjoint(with: negatives)
        }
        return Int((Double(matched.count) / Double(card.exercises.count)) * 100)
    }

    private func animateLandmarkMovement() {
        guard animatesEntrance else {
            for movement in summary.muscleMovements {
                animatedMovements[movement.muscle] = movement.setsAfter
            }
            return
        }

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

private struct LandmarkAppearModifier: ViewModifier {
    let index: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.helmStaggeredAppear(index: index)
        } else {
            content
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
                genre: "Hip-Hop",
                bpm: 171
            ),
            SessionMusicSegment(
                startOffsetSeconds: 180,
                endOffsetSeconds: 540,
                title: "POWER",
                artist: "Kanye West",
                genre: "Hip-Hop",
                bpm: 154
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
                genre: "Electronic",
                bpm: 124
            ),
            SessionMusicSegment(
                startOffsetSeconds: 21,
                endOffsetSeconds: 236,
                title: "Not Enough",
                artist: "Dam Swindle",
                genre: "Electronic",
                bpm: 118
            ),
            SessionMusicSegment(
                startOffsetSeconds: 236,
                endOffsetSeconds: 245,
                title: "More Than It Seems",
                artist: "KOLA",
                genre: "Electronic",
                bpm: 122
            ),
            SessionMusicSegment(
                startOffsetSeconds: 245,
                endOffsetSeconds: 336,
                title: "Two Hearts, Come Through",
                artist: "BowAsWell",
                genre: "Electronic",
                bpm: nil
            ),
            SessionMusicSegment(
                startOffsetSeconds: 336,
                endOffsetSeconds: 420,
                title: "Encore",
                artist: "Various",
                genre: "Electronic",
                bpm: 128
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
