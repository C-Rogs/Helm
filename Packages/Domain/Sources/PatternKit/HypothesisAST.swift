import Foundation

public enum ExposureOp: String, Sendable, Hashable, Codable, CaseIterable {
    case present
    case absent
    case tertileLow = "tertile_low"
    case tertileHigh = "tertile_high"
    case bandEquals = "band_equals"
    case residualPositive = "residual_positive"
    case residualNonPositive = "residual_non_positive"
}

public struct ExposureSpec: Sendable, Hashable, Codable, Equatable {
    public var field: DayFeatureField
    public var op: ExposureOp
    public var band: String?

    public init(field: DayFeatureField, op: ExposureOp, band: String? = nil) {
        self.field = field
        self.op = op
        self.band = band
    }
}

public struct OutcomeSpec: Sendable, Hashable, Codable, Equatable {
    public var field: DayFeatureField

    public init(field: DayFeatureField) {
        self.field = field
    }
}

public struct MatchingCriteria: Sendable, Hashable, Codable, Equatable {
    public var requireTrainingDay: Bool
    public var sameWeekdayAsExposure: Bool

    public init(requireTrainingDay: Bool = false, sameWeekdayAsExposure: Bool = false) {
        self.requireTrainingDay = requireTrainingDay
        self.sameWeekdayAsExposure = sameWeekdayAsExposure
    }

    public static let none = MatchingCriteria()
    public static let trainingDay = MatchingCriteria(requireTrainingDay: true)
}

public enum CopyRegister: String, Sendable, Hashable, Codable {
    case educational
    case tentative
    case confirmed
    case softContext = "soft_context"
    case suppressed
    case sampleTooSmall = "sample_too_small"
    case null
}

public struct LiteraturePrior: Sendable, Hashable, Codable, Equatable {
    public var mu0: Double
    public var sigma0: Double
    public var unit: String
    public var educationalCopy: String
    public var minNToUpdate: Int

    public init(
        mu0: Double,
        sigma0: Double,
        unit: String,
        educationalCopy: String,
        minNToUpdate: Int = 5
    ) {
        self.mu0 = mu0
        self.sigma0 = sigma0
        self.unit = unit
        self.educationalCopy = educationalCopy
        self.minNToUpdate = minNToUpdate
    }
}

public struct HypothesisSpec: Sendable, Hashable, Codable, Equatable {
    public var id: String
    public var exposure: ExposureSpec
    public var outcome: OutcomeSpec
    public var lag: Int
    public var match: MatchingCriteria
    public var copyRegisterHint: CopyRegister
    public var prior: LiteraturePrior?

    public init(
        id: String,
        exposure: ExposureSpec,
        outcome: OutcomeSpec,
        lag: Int,
        match: MatchingCriteria = .none,
        copyRegisterHint: CopyRegister = .tentative,
        prior: LiteraturePrior? = nil
    ) {
        self.id = id
        self.exposure = exposure
        self.outcome = outcome
        self.lag = lag
        self.match = match
        self.copyRegisterHint = copyRegisterHint
        self.prior = prior
    }
}

public enum HypothesisCompileError: Error, Equatable, Sendable {
    case unknownField
    case illegalOpForField(DayFeatureField, ExposureOp)
    case lagOutOfRange(Int)
    case missingBand
    case emptyID
}

public enum HypothesisCompiler {
    public static func compile(_ spec: HypothesisSpec) -> Result<HypothesisSpec, HypothesisCompileError> {
        guard !spec.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyID)
        }
        guard spec.lag >= 0, spec.lag <= PatternKit.maxLag else {
            return .failure(.lagOutOfRange(spec.lag))
        }
        if !isOpLegal(spec.exposure.op, for: spec.exposure.field) {
            return .failure(.illegalOpForField(spec.exposure.field, spec.exposure.op))
        }
        if spec.exposure.op == .bandEquals, (spec.exposure.band ?? "").isEmpty {
            return .failure(.missingBand)
        }
        switch spec.outcome.field.kind {
        case .continuous, .residual:
            break
        case .binary, .categorical:
            return .failure(.illegalOpForField(spec.outcome.field, spec.exposure.op))
        }
        return .success(spec)
    }

    public static func decodeJSON(_ data: Data) -> Result<HypothesisSpec, HypothesisCompileError> {
        guard let spec = try? JSONDecoder().decode(HypothesisSpec.self, from: data) else {
            return .failure(.unknownField)
        }
        return compile(spec)
    }

    public static func isOpLegal(_ op: ExposureOp, for field: DayFeatureField) -> Bool {
        switch (field.kind, op) {
        case (.binary, .present), (.binary, .absent):
            true
        case (.continuous, .tertileLow), (.continuous, .tertileHigh):
            true
        case (.residual, .residualPositive), (.residual, .residualNonPositive),
             (.residual, .tertileLow), (.residual, .tertileHigh):
            true
        case (.categorical, .bandEquals):
            true
        default:
            false
        }
    }

    public static func canonicalID(for spec: HypothesisSpec) -> String {
        let trimmed = spec.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return astKey(spec)
    }

    /// Exposure × outcome × lag × match, ignoring display id. Dedupes LLM vs search ids.
    public static func astKey(_ spec: HypothesisSpec) -> String {
        [
            spec.exposure.field.rawValue,
            spec.exposure.op.rawValue,
            spec.exposure.band ?? "",
            spec.outcome.field.rawValue,
            "lag\(spec.lag)",
            spec.match.requireTrainingDay ? "train" : "",
            spec.match.sameWeekdayAsExposure ? "wd" : ""
        ].joined(separator: "_")
    }
}
