import Core
import Foundation
import GRDB

public struct StoredPatternFinding: Sendable, Equatable, Identifiable {
    public var id: String
    public var astJSON: String
    public var status: String
    public var verdict: String
    public var nExp: Int
    public var nCtrl: Int
    public var cliffsDelta: Double?
    public var medianDelta: Double?
    public var permutationP: Double?
    public var fdrQ: Double?
    public var ciLow: Double?
    public var ciHigh: Double?
    public var copyRegister: String
    public var headline: String
    public var body: String
    public var firstDetectedAt: Date
    public var updatedAt: Date
    public var posteriorMu: Double?
    public var posteriorSigma: Double?
    public var eValue: Double?

    public init(
        id: String,
        astJSON: String,
        status: String,
        verdict: String,
        nExp: Int,
        nCtrl: Int,
        cliffsDelta: Double?,
        medianDelta: Double?,
        permutationP: Double?,
        fdrQ: Double?,
        ciLow: Double?,
        ciHigh: Double?,
        copyRegister: String,
        headline: String,
        body: String,
        firstDetectedAt: Date,
        updatedAt: Date,
        posteriorMu: Double? = nil,
        posteriorSigma: Double? = nil,
        eValue: Double? = nil
    ) {
        self.id = id
        self.astJSON = astJSON
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
}

public struct StoredPatternFDRState: Sendable, Equatable {
    public var wealth0: Double
    public var alphaEarn: Double
    public var testIndex: Int
    public var rejectionTimesJSON: String
    public var spentIDsJSON: String
    public var lastDiscoveryAt: Date?

    public init(
        wealth0: Double,
        alphaEarn: Double,
        testIndex: Int,
        rejectionTimesJSON: String,
        spentIDsJSON: String,
        lastDiscoveryAt: Date?
    ) {
        self.wealth0 = wealth0
        self.alphaEarn = alphaEarn
        self.testIndex = testIndex
        self.rejectionTimesJSON = rejectionTimesJSON
        self.spentIDsJSON = spentIDsJSON
        self.lastDiscoveryAt = lastDiscoveryAt
    }
}

public struct PatternFindingStore: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func upsert(_ finding: StoredPatternFinding) throws {
        try pool.write { db in
            try PatternFindingRecord(finding: finding).save(db)
        }
    }

    public func upsertAll(_ findings: [StoredPatternFinding]) throws {
        try pool.write { db in
            for finding in findings {
                try PatternFindingRecord(finding: finding).save(db)
            }
        }
    }

    public func fetchAll() throws -> [StoredPatternFinding] {
        try pool.read { db in
            try PatternFindingRecord
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { try $0.toValue() }
        }
    }

    public func fetch(id: String) throws -> StoredPatternFinding? {
        try pool.read { db in
            try PatternFindingRecord.fetchOne(db, key: id)?.toValue()
        }
    }

    public func fetch(statuses: [String]) throws -> [StoredPatternFinding] {
        guard !statuses.isEmpty else { return [] }
        let placeholders = statuses.map { _ in "?" }.joined(separator: ",")
        return try pool.read { db in
            try PatternFindingRecord
                .filter(sql: "status IN (\(placeholders))", arguments: StatementArguments(statuses))
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .map { try $0.toValue() }
        }
    }

    public func markMemoryConfirmed(id: String, at date: Date = Date()) throws {
        try pool.write { db in
            guard var record = try PatternFindingRecord.fetchOne(db, key: id) else { return }
            record.status = "memory_confirmed"
            record.copyRegister = "confirmed"
            record.updatedAt = ISO8601Coding.string(from: date)
            try record.update(db)
        }
    }

    public func loadFDRState() throws -> StoredPatternFDRState? {
        try pool.read { db in
            try PatternFDRStateRecord.fetchOne(db, key: 1)?.toValue()
        }
    }

    public func saveFDRState(_ state: StoredPatternFDRState) throws {
        try pool.write { db in
            try PatternFDRStateRecord(state: state).save(db)
        }
    }
}

private struct PatternFindingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pattern_finding"

    enum CodingKeys: String, CodingKey {
        case id
        case astJSON = "ast_json"
        case status
        case verdict
        case nExp = "n_exp"
        case nCtrl = "n_ctrl"
        case cliffsDelta = "cliffs_delta"
        case medianDelta = "median_delta"
        case permutationP = "permutation_p"
        case fdrQ = "fdr_q"
        case ciLow = "ci_low"
        case ciHigh = "ci_high"
        case copyRegister = "copy_register"
        case headline
        case body
        case firstDetectedAt = "first_detected_at"
        case updatedAt = "updated_at"
        case posteriorMu = "posterior_mu"
        case posteriorSigma = "posterior_sigma"
        case eValue = "e_value"
    }

    var id: String
    var astJSON: String
    var status: String
    var verdict: String
    var nExp: Int
    var nCtrl: Int
    var cliffsDelta: Double?
    var medianDelta: Double?
    var permutationP: Double?
    var fdrQ: Double?
    var ciLow: Double?
    var ciHigh: Double?
    var copyRegister: String
    var headline: String
    var body: String
    var firstDetectedAt: String
    var updatedAt: String
    var posteriorMu: Double?
    var posteriorSigma: Double?
    var eValue: Double?

    init(finding: StoredPatternFinding) {
        id = finding.id
        astJSON = finding.astJSON
        status = finding.status
        verdict = finding.verdict
        nExp = finding.nExp
        nCtrl = finding.nCtrl
        cliffsDelta = finding.cliffsDelta
        medianDelta = finding.medianDelta
        permutationP = finding.permutationP
        fdrQ = finding.fdrQ
        ciLow = finding.ciLow
        ciHigh = finding.ciHigh
        copyRegister = finding.copyRegister
        headline = finding.headline
        body = finding.body
        firstDetectedAt = ISO8601Coding.string(from: finding.firstDetectedAt)
        updatedAt = ISO8601Coding.string(from: finding.updatedAt)
        posteriorMu = finding.posteriorMu
        posteriorSigma = finding.posteriorSigma
        eValue = finding.eValue
    }

    func toValue() throws -> StoredPatternFinding {
        StoredPatternFinding(
            id: id,
            astJSON: astJSON,
            status: status,
            verdict: verdict,
            nExp: nExp,
            nCtrl: nCtrl,
            cliffsDelta: cliffsDelta,
            medianDelta: medianDelta,
            permutationP: permutationP,
            fdrQ: fdrQ,
            ciLow: ciLow,
            ciHigh: ciHigh,
            copyRegister: copyRegister,
            headline: headline,
            body: body,
            firstDetectedAt: try ISO8601Coding.date(from: firstDetectedAt),
            updatedAt: try ISO8601Coding.date(from: updatedAt),
            posteriorMu: posteriorMu,
            posteriorSigma: posteriorSigma,
            eValue: eValue
        )
    }
}

private struct PatternFDRStateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pattern_fdr_state"

    enum CodingKeys: String, CodingKey {
        case id
        case wealth0
        case alphaEarn = "alpha_earn"
        case testIndex = "test_index"
        case rejectionTimesJSON = "rejection_times_json"
        case spentIDsJSON = "spent_ids_json"
        case lastDiscoveryAt = "last_discovery_at"
        case updatedAt = "updated_at"
    }

    var id: Int
    var wealth0: Double
    var alphaEarn: Double
    var testIndex: Int
    var rejectionTimesJSON: String
    var spentIDsJSON: String
    var lastDiscoveryAt: String?
    var updatedAt: String

    init(state: StoredPatternFDRState) {
        id = 1
        wealth0 = state.wealth0
        alphaEarn = state.alphaEarn
        testIndex = state.testIndex
        rejectionTimesJSON = state.rejectionTimesJSON
        spentIDsJSON = state.spentIDsJSON
        lastDiscoveryAt = state.lastDiscoveryAt.map(ISO8601Coding.string(from:))
        updatedAt = ISO8601Coding.string(from: Date())
    }

    func toValue() -> StoredPatternFDRState {
        StoredPatternFDRState(
            wealth0: wealth0,
            alphaEarn: alphaEarn,
            testIndex: testIndex,
            rejectionTimesJSON: rejectionTimesJSON,
            spentIDsJSON: spentIDsJSON,
            lastDiscoveryAt: lastDiscoveryAt.flatMap { try? ISO8601Coding.date(from: $0) }
        )
    }
}
