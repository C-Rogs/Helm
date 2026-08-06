import Core
import Foundation

/// What a logged set contributes to the ledger, independent of how it was tagged.
public enum SetStimulusRole: Sendable, Hashable, Codable {
    /// A self-contained working set graded against the full rep and load bands.
    case topWorking
    /// A continuation of a preceding working set (drop, rest-pause mini-set).
    /// Rep and load bands do not apply: the extension inherits the parent set's context.
    case intensityExtension
    /// Warmups and unloaded modalities. No stimulus, no fatigue.
    case excluded

    public init(_ setType: SetType) {
        switch setType {
        case .warmup, .assisted, .timed, .distance:
            self = .excluded
        case .dropSet, .restPauseFollowUp:
            self = .intensityExtension
        case .normal, .failure, .bodyweight, .restPauseActivation:
            self = .topWorking
        }
    }
}

/// Stimulus and fatigue are tracked separately: MEV is a stimulus construct, MRV a fatigue one.
///
/// Conflating them means a set of 3 at RPE 10 and a set of 12 at RPE 8 both read as "1 set",
/// which is wrong in both directions: the heavy single under-reads its recovery cost and
/// over-reads its hypertrophic contribution.
public struct SetLedgerCredit: Sendable, Hashable, Codable {
    /// Hypertrophic contribution, counted against MEV and the weekly target.
    public let stimulus: Double
    /// Recovery cost, counted against MRV.
    public let fatigue: Double

    public init(stimulus: Double, fatigue: Double) {
        self.stimulus = max(0, stimulus)
        self.fatigue = max(0, fatigue)
    }

    public static let none = SetLedgerCredit(stimulus: 0, fatigue: 0)

    public var isCredited: Bool { stimulus > 0 || fatigue > 0 }

    public func scaled(by factor: Double) -> SetLedgerCredit {
        SetLedgerCredit(stimulus: stimulus * factor, fatigue: fatigue * factor)
    }
}

/// Diminishing returns on stimulus within a single session for one muscle.
///
/// Remmert et al. (2025) meta-regressed per-session volume and placed the point of
/// undetectable outcome superiority at ~11 fractional sets for hypertrophy, with returns
/// diminishing progressively below that rather than falling off a cliff above it. A
/// piecewise-linear taper reproduces that shape while staying order-independent: the
/// discount depends only on the session total, so it cannot change when sets are reordered.
public struct SessionSaturation: Sendable, Hashable, Codable {
    /// Raw fractional sets credited in full.
    public var freeZone: Double
    /// Width of the taper above `freeZone`, over which marginal credit falls to `floor`.
    public var taperSpan: Double
    /// Marginal credit retained once the taper is exhausted.
    public var floor: Double

    public init(freeZone: Double = 6.0, taperSpan: Double = 8.0, floor: Double = 0.25) {
        self.freeZone = max(0, freeZone)
        self.taperSpan = max(0, taperSpan)
        self.floor = min(max(0, floor), 1)
    }

    public static let standard = SessionSaturation()

    /// Effective fractional sets for a raw per-muscle, per-session total.
    ///
    /// Saturating at ~11 effective sets for a 14-set session matches the meta-regression's
    /// plateau without ever returning less credit for more work.
    public func effective(_ raw: Double) -> Double {
        guard raw > freeZone else { return max(0, raw) }
        let over = raw - freeZone
        guard taperSpan > 0 else { return freeZone + over * floor }
        if over >= taperSpan {
            let taperArea = taperSpan * (1 + floor) / 2
            return freeZone + taperArea + (over - taperSpan) * floor
        }
        // Marginal credit falls linearly 1 -> floor across the taper; integrate it.
        let marginalAtOver = 1 - (1 - floor) * (over / taperSpan)
        return freeZone + over * (1 + marginalAtOver) / 2
    }
}

/// Tunable constants for the stimulus/fatigue ledger.
///
/// Kept in one value type so the physiological model can be swapped per athlete, unit-tested
/// against fixtures, and audited against the literature without hunting through call sites.
public struct HardSetPolicy: Sendable, Hashable, Codable {
    // MARK: Proximity to failure

    /// Sets at or below this RIR earn undiscounted stimulus.
    ///
    /// Refalo et al. (2023) found no hypertrophy advantage for training to momentary failure
    /// over stopping short, so RIR 0 and RIR 2 are treated alike.
    public var fullCreditRIR: Int = 2
    /// Above this RIR a set is a warmup and earns nothing.
    public var warmupRIRThreshold: Int = 6

    // MARK: Rep and load bands

    /// Rep range earning undiscounted stimulus.
    public var hypertrophyRepRange: ClosedRange<Int> = 5 ... 30
    /// Credit for sets below the rep range. Heavy work still grows muscle, just less per set.
    public var lowRepStrengthCredit: Double = 0.5
    /// Credit for sets above the rep range.
    public var highRepEnduranceCredit: Double = 0.5
    /// Loads under this fraction of reference 1RM are warmups regardless of tagging.
    public var minLoadFractionOf1RM: Double = 0.30

    // MARK: Intensity techniques

    /// Credit for the reduced-load portion of a drop set.
    public var dropSetCredit: Double = 0.5
    /// Credit per rest-pause mini-set before aggregation.
    public var restPauseFollowUpCredit: Double = 0.5
    /// All rest-pause mini-sets after one activation set aggregate to at most this much.
    public var restPauseAggregateCap: Double = 0.5
    /// Ceiling on combined intensity-technique credit per exercise.
    public var intensityTechniquePrimaryCap: Double = 1.5

    // MARK: Volume ceilings

    /// Indirect work may satisfy at most this share of a muscle's weekly target.
    public var synergistWeeklyCapFraction: Double = 0.5
    public var sessionSaturation: SessionSaturation = .standard

    // MARK: Reference 1RM

    /// Epley loses accuracy past this rep count, so higher-rep sets do not set the reference.
    public var maxRepsForE1RMEstimate: Int = 12
    /// Days a reference 1RM holds before detraining decay applies.
    public var e1rmDecayGraceDays: Double = 14
    /// Exponential decay rate applied after the grace period.
    public var e1rmDecayPerDay: Double = 0.005

    public static let standard = HardSetPolicy()

    public init() {}

    /// Stimulus multiplier for proximity to failure.
    ///
    /// Robinson et al. (2024) found hypertrophy increases continuously as sets approach
    /// failure: a negative linear slope on RIR, not a threshold. A binary gate at RIR 4
    /// would credit an RIR-4 set identically to an RIR-0 set and an RIR-5 set not at all,
    /// which the dose-response data does not support in either direction.
    public func proximityCredit(rir: Double?) -> Double {
        guard let rir else { return 1.0 }
        if rir <= Double(fullCreditRIR) { return 1.0 }
        if rir >= Double(warmupRIRThreshold) { return 0 }
        switch rir {
        case ..<4: return 0.9
        case ..<5: return 0.8
        default: return 0.5
        }
    }

    /// Stimulus multiplier for the rep band.
    public func repBandCredit(reps: Int) -> Double {
        if reps < hypertrophyRepRange.lowerBound { return lowRepStrengthCredit }
        if reps > hypertrophyRepRange.upperBound { return highRepEnduranceCredit }
        return 1.0
    }

    /// Recovery cost of a set, rising with effort.
    ///
    /// Mirrors the research spec's RPE-weighted load term rather than inventing multipliers:
    /// a set at RPE 10 costs ~1.3x a set at RPE 7.
    public func fatigueCost(rpe: Double?) -> Double {
        guard let rpe else { return 1.0 }
        return max(0, 1.0 + 0.1 * (rpe - 7.0))
    }
}
