import Core
import Foundation

public enum PersonalRecordDetector {
    public static func detect(
        in session: WorkoutSessionDraft,
        repository: WorkoutSessionRepository
    ) throws -> [DetectedPersonalRecord] {
        guard session.status == .completed else { return [] }

        var detected: [DetectedPersonalRecord] = []

        for exercise in session.exercises {
            for set in exercise.sets where set.status == .completed && !set.setType.isWarmup {
                if let mass = set.mass {
                    let historicalMax = try repository.maxWeight(
                        exerciseID: exercise.exerciseID,
                        excludingSessionID: session.id
                    )
                    if historicalMax == nil || mass.kilograms > (historicalMax ?? 0) {
                        detected.append(
                            DetectedPersonalRecord(
                                exerciseID: exercise.exerciseID,
                                metricType: .maxWeight,
                                metricValue: mass.kilograms,
                                sourceSetEntryID: set.id,
                                previousBest: historicalMax
                            )
                        )
                    }

                    if let reps = set.reps, reps > 0 {
                        let e1rm = EpleyOneRepMax.estimate(mass: mass, reps: reps).kilograms
                        let historicalE1RM = try repository.estimatedOneRM(
                            exerciseID: exercise.exerciseID,
                            excludingSessionID: session.id
                        )?.kilograms
                        if historicalE1RM == nil || e1rm > (historicalE1RM ?? 0) {
                            detected.append(
                                DetectedPersonalRecord(
                                    exerciseID: exercise.exerciseID,
                                    metricType: .bestEstimated1RM,
                                    metricValue: e1rm,
                                    sourceSetEntryID: set.id,
                                    previousBest: historicalE1RM
                                )
                            )
                        }

                        let historicalReps = try repository.maxReps(
                            exerciseID: exercise.exerciseID,
                            atWeightKilograms: mass.kilograms,
                            excludingSessionID: session.id
                        )
                        if historicalReps == nil || reps > (historicalReps ?? 0) {
                            detected.append(
                                DetectedPersonalRecord(
                                    exerciseID: exercise.exerciseID,
                                    metricType: .maxRepsAtWeight,
                                    metricValue: Double(reps),
                                    sourceSetEntryID: set.id,
                                    previousBest: historicalReps.map(Double.init)
                                )
                            )
                        }
                    }
                }
            }
        }

        return deduplicated(detected)
    }

    private static func deduplicated(_ records: [DetectedPersonalRecord]) -> [DetectedPersonalRecord] {
        var bestByKey: [String: DetectedPersonalRecord] = [:]
        for record in records {
            let key = "\(record.exerciseID)|\(record.metricType.rawValue)"
            if let existing = bestByKey[key] {
                if record.metricValue > existing.metricValue {
                    bestByKey[key] = record
                }
            } else {
                bestByKey[key] = record
            }
        }
        return bestByKey.values.sorted {
            $0.exerciseID < $1.exerciseID || ($0.exerciseID == $1.exerciseID && $0.metricType.rawValue < $1.metricType.rawValue)
        }
    }
}
