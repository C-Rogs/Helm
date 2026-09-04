import Foundation

public enum ContrastVerdict: String, Sendable, Hashable, Codable {
    case ship
    case soft
    case suppress
    case killSample = "kill_sample"
    case killNull = "kill_null"
}

public enum FindingStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case priorSeed = "prior_seed"
    case emerging
    case stable
    case retired
    case memoryConfirmed = "memory_confirmed"
}

public struct ContrastResult: Sendable, Equatable {
    public var spec: HypothesisSpec
    public var nExp: Int
    public var nCtrl: Int
    public var medianExp: Double?
    public var medianCtrl: Double?
    public var medianDelta: Double?
    public var cliffs: CliffsDeltaEstimate?
    public var permutationP: Double?
    public var fdrQ: Double?
    public var posteriorMu: Double?
    public var posteriorSigma: Double?
    public var eValue: Double?
    public var verdict: ContrastVerdict
    public var notes: String

    public init(
        spec: HypothesisSpec,
        nExp: Int,
        nCtrl: Int,
        medianExp: Double? = nil,
        medianCtrl: Double? = nil,
        medianDelta: Double? = nil,
        cliffs: CliffsDeltaEstimate? = nil,
        permutationP: Double? = nil,
        fdrQ: Double? = nil,
        posteriorMu: Double? = nil,
        posteriorSigma: Double? = nil,
        eValue: Double? = nil,
        verdict: ContrastVerdict,
        notes: String = ""
    ) {
        self.spec = spec
        self.nExp = nExp
        self.nCtrl = nCtrl
        self.medianExp = medianExp
        self.medianCtrl = medianCtrl
        self.medianDelta = medianDelta
        self.cliffs = cliffs
        self.permutationP = permutationP
        self.fdrQ = fdrQ
        self.posteriorMu = posteriorMu
        self.posteriorSigma = posteriorSigma
        self.eValue = eValue
        self.verdict = verdict
        self.notes = notes
    }
}

public struct PatternFinding: Sendable, Hashable, Codable, Equatable, Identifiable {
    public var id: String
    public var spec: HypothesisSpec
    public var status: FindingStatus
    public var verdict: ContrastVerdict
    public var nExp: Int
    public var nCtrl: Int
    public var cliffsDelta: Double?
    public var medianDelta: Double?
    public var permutationP: Double?
    public var fdrQ: Double?
    public var ciLow: Double?
    public var ciHigh: Double?
    public var copyRegister: CopyRegister
    public var headline: String
    public var body: String
    public var firstDetectedAt: Date
    public var updatedAt: Date
    public var posteriorMu: Double?
    public var posteriorSigma: Double?
    public var eValue: Double?

    public init(
        id: String,
        spec: HypothesisSpec,
        status: FindingStatus,
        verdict: ContrastVerdict,
        nExp: Int,
        nCtrl: Int,
        cliffsDelta: Double?,
        medianDelta: Double?,
        permutationP: Double?,
        fdrQ: Double?,
        ciLow: Double?,
        ciHigh: Double?,
        copyRegister: CopyRegister,
        headline: String,
        body: String,
        firstDetectedAt: Date,
        updatedAt: Date,
        posteriorMu: Double? = nil,
        posteriorSigma: Double? = nil,
        eValue: Double? = nil
    ) {
        self.id = id
        self.spec = spec
        self.status = status
        self.verdict = verdict
        self.nExp = nExp
        self.nCtrl = nCtrl
        self.cliffsDelta = cliffsDelta
        self.medianDelta = medianDelta
        self.permutationP = permutationP
        self.fdrQ = fdrQ
        self.ciLow = ciLow
        self.ciHigh = ciHigh
        self.copyRegister = copyRegister
        self.headline = headline
        self.body = body
        self.firstDetectedAt = firstDetectedAt
        self.updatedAt = updatedAt
        self.posteriorMu = posteriorMu
        self.posteriorSigma = posteriorSigma
        self.eValue = eValue
    }

    public var cardText: String {
        "\(headline)\n\(body)"
    }
}
