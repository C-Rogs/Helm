import Core
import Foundation

/// One candidate training plan produced by `CandidatePlanGenerator`.
///
/// All stats are computed from engine landmarks, not authored copy: the LLM
/// layer only writes presentation text on top of these facts.
public struct CandidatePlan: Sendable, Hashable, Codable, Identifiable {
    /// Stable key used by UI + LLM copy mapping (e.g. "ppl_4day_highfreq").
    public let id: String
    public let headline: String
    /// Program template to persist if this candidate is chosen.
    public let programTemplateRaw: String
    public let daysPerWeek: Int
    public let sessionDurationMinutes: Int
    /// Weekly hard sets per muscle at peak (pre-deload) week, from landmark seeding.
    public let weeklyPeakSetsByMuscle: [MuscleGroup: Int]
    /// Sessions per muscle per week implied by the split.
    public let frequencyByMuscle: [MuscleGroup: Int]
    /// Deload cadence in weeks from the mesocycle block length.
    public let deloadCadenceWeeks: Int
    /// 0.0...1.0: how well the split fits the athlete's stated availability.
    public let availabilityFitScore: Double
    /// Deterministic rationale notes derived from levers.
    public let leverNotes: [String]

    public init(
        id: String,
        headline: String,
        programTemplateRaw: String,
        daysPerWeek: Int,
        sessionDurationMinutes: Int,
        weeklyPeakSetsByMuscle: [MuscleGroup: Int],
        frequencyByMuscle: [MuscleGroup: Int],
        deloadCadenceWeeks: Int,
        availabilityFitScore: Double,
        leverNotes: [String]
    ) {
        self.id = id
        self.headline = headline
        self.programTemplateRaw = programTemplateRaw
        self.daysPerWeek = daysPerWeek
        self.sessionDurationMinutes = sessionDurationMinutes
        self.weeklyPeakSetsByMuscle = weeklyPeakSetsByMuscle
        self.frequencyByMuscle = frequencyByMuscle
        self.deloadCadenceWeeks = deloadCadenceWeeks
        self.availabilityFitScore = availabilityFitScore
        self.leverNotes = leverNotes
    }
}

/// Generates 3-4 distinct candidate plans from interview answers using existing
/// PlanKit landmark and mesocycle math. Zero I/O, fully deterministic.
public enum CandidatePlanGenerator {
    /// Matches the engine's default mesocycle block length (deload cadence).
    public static let defaultBlockLengthWeeks = 5

    /// Typed view of the interview's experience raw value for landmark seeding.
    public static func experience(of interview: PlanBuilderInterview) -> TrainingExperience {
        TrainingExperience(rawValue: interview.experienceRaw) ?? .intermediate
    }

    /// Levers per availability bucket. PPL slots are live for all templates;
    /// upper/full candidates reuse PPL day mapping via `hasDedicatedSlotTables`.
    static func candidateBlueprints(daysPerWeek: Int) -> [CandidateBlueprint] {
        switch daysPerWeek {
        case ...2:
            return [
                CandidateBlueprint(
                    id: "fullbody_2day",
                    headline: "Two full-body sessions",
                    templateRaw: "ppl",
                    dayKindRotation: [.full, .full],
                    fitScore: 1.0
                ),
                CandidateBlueprint(
                    id: "upperlower_2day",
                    headline: "Upper / lower split",
                    templateRaw: "ppl",
                    dayKindRotation: [.upper, .lower],
                    fitScore: 0.9
                )
            ]
        case 3:
            return [
                CandidateBlueprint(
                    id: "ppl_3day",
                    headline: "Push / Pull / Legs rotation",
                    templateRaw: "ppl",
                    dayKindRotation: [.push, .pull, .legs],
                    fitScore: 1.0
                ),
                CandidateBlueprint(
                    id: "fullbody_3day",
                    headline: "Three full-body sessions",
                    templateRaw: "ppl",
                    dayKindRotation: [.full, .full, .full],
                    fitScore: 0.85
                ),
                CandidateBlueprint(
                    id: "upper_emphasis_3day",
                    headline: "Upper-biased three-day split",
                    templateRaw: "ppl",
                    dayKindRotation: [.upper, .pull, .legs],
                    fitScore: 0.8
                )
            ]
        case 4:
            return [
                CandidateBlueprint(
                    id: "upperlower_4day",
                    headline: "Four-day upper / lower",
                    templateRaw: "ppl",
                    dayKindRotation: [.upper, .lower, .upper, .lower],
                    fitScore: 1.0
                ),
                CandidateBlueprint(
                    id: "ppl_4day_hybrid",
                    headline: "PPL plus upper hybrid",
                    templateRaw: "ppl",
                    dayKindRotation: [.push, .pull, .legs, .upper],
                    fitScore: 0.95
                ),
                CandidateBlueprint(
                    id: "pplplus_4day",
                    headline: "PPL with a second push day",
                    templateRaw: "ppl",
                    dayKindRotation: [.push, .pull, .legs, .push],
                    fitScore: 0.8
                )
            ]
        default:
            return [
                CandidateBlueprint(
                    id: "ppl_5day",
                    headline: "Five-day PPL cycle",
                    templateRaw: "ppl",
                    dayKindRotation: [.push, .pull, .legs, .push, .pull],
                    fitScore: 1.0
                ),
                CandidateBlueprint(
                    id: "upperlower_5day",
                    headline: "Upper / lower plus arms",
                    templateRaw: "ppl",
                    dayKindRotation: [.upper, .lower, .upper, .lower, .arms],
                    fitScore: 0.85
                ),
                CandidateBlueprint(
                    id: "bro_6day",
                    headline: "Six-day high-frequency split",
                    templateRaw: "ppl",
                    dayKindRotation: [.push, .pull, .legs, .upper, .lower, .full],
                    fitScore: 0.7
                )
            ]
        }
    }

    /// Produces deterministic candidate plans. Same inputs always yield same outputs.
    public static func generate(
        interview: PlanBuilderInterview,
        experience: TrainingExperience,
        historicalWeeklyHardSets: [MuscleGroup: Double] = [:]
    ) -> [CandidatePlan] {
        candidateBlueprints(daysPerWeek: interview.daysPerWeek)
            .map { blueprint in
                makeCandidate(
                    blueprint: blueprint,
                    interview: interview,
                    experience: experience,
                    historicalWeeklyHardSets: historicalWeeklyHardSets
                )
            }
    }

    static func makeCandidate(
        blueprint: CandidateBlueprint,
        interview: PlanBuilderInterview,
        experience: TrainingExperience,
        historicalWeeklyHardSets: [MuscleGroup: Double]
    ) -> CandidatePlan {
        // Volume multiplier: recomposition trims toward MEV side, hypertrophy rides mid-ramp.
        let goalMultiplier: Double
        var notes: [String] = []
        switch interview.progressionGoal {
        case .strength:
            goalMultiplier = 0.85
            notes.append("Volume trimmed ~15% so heavy compounds stay fresh.")
        case .hypertrophy:
            goalMultiplier = 1.0
        case .recomposition:
            goalMultiplier = 0.92
            notes.append("Slightly reduced volume supports recovery in a deficit.")
        }

        var peakSets: [MuscleGroup: Int] = [:]
        var frequency: [MuscleGroup: Int] = [:]
        for muscle in MuscleGroup.allCases {
            let landmarks = MesocycleEngine.seedLandmarks(
                muscle: muscle,
                experience: experience,
                historicalWeeklyHardSets: historicalWeeklyHardSets[muscle]
            )
            let trained = blueprint.musclesTrained.contains(muscle)
            let rawPeak = Double(landmarks.mev) + goalMultiplier * Double(landmarks.mrv - landmarks.mev) * 0.6
            let scaled = trained ? max(landmarks.mev, Int(rawPeak.rounded())) : 0
            peakSets[muscle] = scaled

            let hitDays = blueprint.dayKindRotation.filter { kind in
                Self.dayKindMuscles(kind).contains(muscle)
            }.count
            frequency[muscle] = hitDays
        }

        if blueprint.dayKindRotation.count > interview.daysPerWeek {
            notes.append("Split compresses into \(interview.daysPerWeek) available days when life gets busy.")
        }
        if blueprint.dayKindRotation.allSatisfy({ Self.dayKindMuscles($0).count >= 4 }) {
            notes.append("Full-body days spread volume thin; expect shorter per-muscle blocks.")
        }
        if interview.sessionDurationMinutes <= 45 {
            notes.append("\(interview.sessionDurationMinutes)-minute budget caps sets per session; volume lands across more days.")
        }

        let fitNotes = blueprint.fitScore < 0.85 ? ["Stretches your stated availability."] : []
        notes.append(contentsOf: fitNotes)

        return CandidatePlan(
            id: blueprint.id,
            headline: blueprint.headline,
            programTemplateRaw: blueprint.templateRaw,
            daysPerWeek: blueprint.dayKindRotation.count,
            sessionDurationMinutes: interview.sessionDurationMinutes,
            weeklyPeakSetsByMuscle: peakSets.filter { $0.value > 0 },
            frequencyByMuscle: frequency.filter { $0.value > 0 },
            deloadCadenceWeeks: CandidatePlanGenerator.defaultBlockLengthWeeks,
            availabilityFitScore: min(1.0, blueprint.fitScore),
            leverNotes: notes
        )
    }

    static func dayKindMuscles(_ kind: TrainingDayKind) -> Set<MuscleGroup> {
        switch kind {
        case .push: [.chest, .shoulders, .triceps]
        case .pull: [.back, .biceps]
        case .legs: [.quads, .hamstrings, .glutes, .calves, .abs]
        case .upper: [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: [.quads, .hamstrings, .glutes, .calves, .abs]
        case .full: Set(MuscleGroup.allCases)
        case .arms: [.biceps, .triceps, .shoulders]
        }
    }
}

struct CandidateBlueprint: Sendable {
    let id: String
    let headline: String
    let templateRaw: String
    let dayKindRotation: [TrainingDayKind]
    let fitScore: Double

    var musclesTrained: Set<MuscleGroup> {
        dayKindRotation.reduce(into: Set<MuscleGroup>()) { acc, kind in
            acc.formUnion(CandidatePlanGenerator.dayKindMuscles(kind))
        }
    }
}
