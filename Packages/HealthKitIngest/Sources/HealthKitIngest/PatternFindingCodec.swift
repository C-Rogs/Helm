import Foundation
import PatternKit
import Persistence

enum PatternFindingCodec {
    static func stored(from finding: PatternFinding) throws -> StoredPatternFinding {
        let data = try JSONEncoder().encode(finding.spec)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return StoredPatternFinding(
            id: finding.id,
            astJSON: json,
            status: finding.status.rawValue,
            verdict: finding.verdict.rawValue,
            nExp: finding.nExp,
            nCtrl: finding.nCtrl,
            cliffsDelta: finding.cliffsDelta,
            medianDelta: finding.medianDelta,
            permutationP: finding.permutationP,
            fdrQ: finding.fdrQ,
            ciLow: finding.ciLow,
            ciHigh: finding.ciHigh,
            copyRegister: finding.copyRegister.rawValue,
            headline: finding.headline,
            body: finding.body,
            firstDetectedAt: finding.firstDetectedAt,
            updatedAt: finding.updatedAt,
            posteriorMu: finding.posteriorMu,
            posteriorSigma: finding.posteriorSigma,
            eValue: finding.eValue
        )
    }

    static func finding(from stored: StoredPatternFinding) throws -> PatternFinding {
        guard let data = stored.astJSON.data(using: .utf8) else {
            throw PatternFindingCodecError.invalidJSON
        }
        let spec = try JSONDecoder().decode(HypothesisSpec.self, from: data)
        return PatternFinding(
            id: stored.id,
            spec: spec,
            status: FindingStatus(rawValue: stored.status) ?? .retired,
            verdict: ContrastVerdict(rawValue: stored.verdict) ?? .killNull,
            nExp: stored.nExp,
            nCtrl: stored.nCtrl,
            cliffsDelta: stored.cliffsDelta,
            medianDelta: stored.medianDelta,
            permutationP: stored.permutationP,
            fdrQ: stored.fdrQ,
            ciLow: stored.ciLow,
            ciHigh: stored.ciHigh,
            copyRegister: CopyRegister(rawValue: stored.copyRegister) ?? .null,
            headline: stored.headline,
            body: stored.body,
            firstDetectedAt: stored.firstDetectedAt,
            updatedAt: stored.updatedAt,
            posteriorMu: stored.posteriorMu,
            posteriorSigma: stored.posteriorSigma,
            eValue: stored.eValue
        )
    }

    static func fdrState(from stored: StoredPatternFDRState) -> LORDPlusPlusState {
        let times = (try? JSONDecoder().decode([Int].self, from: Data(stored.rejectionTimesJSON.utf8))) ?? []
        let spent = (try? JSONDecoder().decode([String].self, from: Data(stored.spentIDsJSON.utf8))) ?? []
        return LORDPlusPlusState(
            wealth0: stored.wealth0,
            alphaEarn: stored.alphaEarn,
            testIndex: stored.testIndex,
            rejectionTimes: times,
            spentIDs: spent
        )
    }

    static func stored(from state: LORDPlusPlusState, lastDiscoveryAt: Date?) throws -> StoredPatternFDRState {
        let times = try String(data: JSONEncoder().encode(state.rejectionTimes), encoding: .utf8) ?? "[]"
        let spent = try String(data: JSONEncoder().encode(state.spentIDs), encoding: .utf8) ?? "[]"
        return StoredPatternFDRState(
            wealth0: state.wealth0,
            alphaEarn: state.alphaEarn,
            testIndex: state.testIndex,
            rejectionTimesJSON: times,
            spentIDsJSON: spent,
            lastDiscoveryAt: lastDiscoveryAt
        )
    }
}

enum PatternFindingCodecError: Error {
    case invalidJSON
}
