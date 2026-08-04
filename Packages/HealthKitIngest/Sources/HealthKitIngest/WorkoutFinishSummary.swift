import Core
import Foundation
import PlanKit

public struct MuscleLandmarkDelta: Sendable, Equatable, Identifiable {
    public let muscle: MuscleGroup
    public let setsBefore: Double
    public let setsAfter: Double
    public let mev: Int
    public let mrv: Int

    public var id: MuscleGroup { muscle }

    public init(
        muscle: MuscleGroup,
        setsBefore: Double,
        setsAfter: Double,
        mev: Int,
        mrv: Int
    ) {
        self.muscle = muscle
        self.setsBefore = setsBefore
        self.setsAfter = setsAfter
        self.mev = mev
        self.mrv = mrv
    }
}

public struct WorkoutFinishSummary: Sendable, Equatable {
    public let setCount: Int
    public let totalVolumeKilograms: Double
    public let estimatedTRIMP: Double
    public let durationMinutes: Int
    public let muscleMovements: [MuscleLandmarkDelta]
    public let readinessTeaser: String
    public let heartRateSamples: [SessionHeartRateSample]
    public let setMarkers: [SessionSetMarker]
    public let exerciseMarkers: [SessionExerciseMarker]
    public let musicSegments: [SessionMusicSegment]

    public var hasHeartRateSeries: Bool { !heartRateSamples.isEmpty }
    public var hasMusicSegments: Bool { !musicSegments.isEmpty }
    public var hasTimelineData: Bool {
        hasHeartRateSeries || !setMarkers.isEmpty || !exerciseMarkers.isEmpty || hasMusicSegments
    }

    public init(
        setCount: Int,
        totalVolumeKilograms: Double,
        estimatedTRIMP: Double,
        durationMinutes: Int,
        muscleMovements: [MuscleLandmarkDelta],
        readinessTeaser: String,
        heartRateSamples: [SessionHeartRateSample] = [],
        setMarkers: [SessionSetMarker] = [],
        exerciseMarkers: [SessionExerciseMarker] = [],
        musicSegments: [SessionMusicSegment] = []
    ) {
        self.setCount = setCount
        self.totalVolumeKilograms = totalVolumeKilograms
        self.estimatedTRIMP = estimatedTRIMP
        self.durationMinutes = durationMinutes
        self.muscleMovements = muscleMovements
        self.readinessTeaser = readinessTeaser
        self.heartRateSamples = heartRateSamples
        self.setMarkers = setMarkers
        self.exerciseMarkers = exerciseMarkers
        self.musicSegments = musicSegments
    }

    public func withSessionTimeline(
        samples: [SessionHeartRateSample],
        setMarkers: [SessionSetMarker],
        exerciseMarkers: [SessionExerciseMarker] = [],
        musicSegments: [SessionMusicSegment] = []
    ) -> WorkoutFinishSummary {
        WorkoutFinishSummary(
            setCount: setCount,
            totalVolumeKilograms: totalVolumeKilograms,
            estimatedTRIMP: estimatedTRIMP,
            durationMinutes: durationMinutes,
            muscleMovements: muscleMovements,
            readinessTeaser: readinessTeaser,
            heartRateSamples: samples,
            setMarkers: setMarkers,
            exerciseMarkers: exerciseMarkers,
            musicSegments: musicSegments
        )
    }

    public func withHeartRate(
        samples: [SessionHeartRateSample],
        setMarkers: [SessionSetMarker]
    ) -> WorkoutFinishSummary {
        withSessionTimeline(samples: samples, setMarkers: setMarkers)
    }
}

public enum WorkoutFinishSummaryBuilder {
    public static func estimatedTRIMP(
        hardSetCount: Int,
        totalReps: Int,
        averageRPE: Double?
    ) -> Double {
        let effort = averageRPE ?? 7.5
        return Double(hardSetCount) * effort * 1.6 + Double(totalReps) * 0.35
    }

    public static func readinessTeaser(setCount: Int, volumeKilograms: Double) -> String {
        if setCount >= 18 || volumeKilograms >= 8_000 {
            return "Heavy load may soften tomorrow's readiness."
        }
        if setCount >= 10 || volumeKilograms >= 4_000 {
            return "Moderate load; readiness should hold steady."
        }
        return "Light session; minimal readiness impact."
    }

    public static func build(
        session: WorkoutSessionDraft,
        sessionMuscleCredits: [MuscleGroup: Double],
        weeklyTotalsAfter: [MuscleGroup: Double],
        landmarks: [MuscleGroup: VolumeLandmarks]
    ) -> WorkoutFinishSummary {
        var hardSetCount = 0
        var totalReps = 0
        var rpeTotal = 0.0
        var rpeCount = 0
        var totalVolume = 0.0

        for exercise in session.exercises {
            for set in exercise.sets where set.status == .completed && !set.setType.isWarmup {
                hardSetCount += 1
                if let reps = set.reps {
                    totalReps += reps
                }
                if let mass = set.mass?.kilograms, let reps = set.reps {
                    totalVolume += mass * Double(reps)
                }
                if let rpe = set.rpe {
                    rpeTotal += rpe
                    rpeCount += 1
                }
            }
        }

        let averageRPE = rpeCount > 0 ? rpeTotal / Double(rpeCount) : nil
        let durationMinutes: Int
        if let endedAt = session.endedAt {
            durationMinutes = max(1, Int(endedAt.timeIntervalSince(session.startedAt) / 60))
        } else {
            durationMinutes = 1
        }

        let movements = sessionMuscleCredits.keys
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { muscle -> MuscleLandmarkDelta? in
                guard let landmarks = landmarks[muscle] else { return nil }
                let credit = sessionMuscleCredits[muscle, default: 0]
                guard credit > 0 else { return nil }
                let after = weeklyTotalsAfter[muscle, default: 0]
                return MuscleLandmarkDelta(
                    muscle: muscle,
                    setsBefore: max(0, after - credit),
                    setsAfter: after,
                    mev: landmarks.mev,
                    mrv: landmarks.mrv
                )
            }
            .sorted { $0.setsAfter > $1.setsAfter }

        return WorkoutFinishSummary(
            setCount: hardSetCount,
            totalVolumeKilograms: totalVolume,
            estimatedTRIMP: estimatedTRIMP(
                hardSetCount: hardSetCount,
                totalReps: totalReps,
                averageRPE: averageRPE
            ),
            durationMinutes: durationMinutes,
            muscleMovements: movements,
            readinessTeaser: readinessTeaser(setCount: hardSetCount, volumeKilograms: totalVolume)
        )
    }
}
