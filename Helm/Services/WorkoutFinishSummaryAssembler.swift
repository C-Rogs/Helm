import Core
import Foundation
import HealthKitIngest
import Persistence
import PlanKit

enum WorkoutFinishSummaryAssembler {
    static func build(
        session: WorkoutSessionDraft,
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> WorkoutFinishSummary {
        let day = HelmDay.day(for: session.startedAt, cutoff: cutoff, calendar: calendar)
        let weekStart = TrendsDataBuilder.weekStart(containing: day, calendar: calendar)
        let sessions = try TrendsDataBuilder.loadSessionsForSummary(
            store: store,
            since: weekStart,
            calendar: calendar,
            cutoff: cutoff
        )
        let muscleMaps = try TrendsDataBuilder.muscleMaps(from: store)
        let ledger = PlanKit.weeklyHardSetTotals(
            sessions: sessions,
            muscleMaps: muscleMaps,
            weekStart: weekStart
        )

        let sessionCredits = sessionMuscleCredits(
            session: session,
            muscleMaps: muscleMaps
        )

        let mesocycle = try TrendsDataBuilder.loadMesocycleState(from: store)
        let settings = try store.trainingPlan.load()
        let experience = TrainingExperience(rawValue: settings.experienceRaw) ?? .intermediate

        var landmarks: [MuscleGroup: VolumeLandmarks] = [:]
        for muscle in sessionCredits.keys {
            landmarks[muscle] = mesocycle?.muscles[muscle]?.landmarks
                ?? PlanKit.seedLandmarks(muscle: muscle, experience: experience)
        }

        return WorkoutFinishSummaryBuilder.build(
            session: session,
            sessionMuscleCredits: sessionCredits,
            weeklyTotalsAfter: ledger.totals,
            landmarks: landmarks
        )
    }

    private static func sessionMuscleCredits(
        session: WorkoutSessionDraft,
        muscleMaps: [String: ExerciseMuscleMap]
    ) -> [MuscleGroup: Double] {
        var credits: [MuscleGroup: Double] = [:]

        for exercise in session.exercises {
            guard let map = muscleMaps[exercise.exerciseID] else { continue }
            for set in exercise.sets where set.status == .completed && !set.setType.isWarmup {
                for contribution in map.contributions {
                    credits[contribution.muscle, default: 0] += contribution.fraction
                }
            }
        }

        return credits
    }
}
