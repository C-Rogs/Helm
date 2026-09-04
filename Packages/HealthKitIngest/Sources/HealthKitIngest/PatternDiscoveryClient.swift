import CoachLLM
import Foundation
import PatternKit
import Persistence

/// Schema-only LLM proposals. ContrastEngine still owns every number.
public enum PatternDiscoveryClient: Sendable {
    public static func propose(
        store: PersistenceStore,
        rows: [DayFeatureRow]? = nil,
        provider: GeminiProvider = GeminiProvider()
    ) async -> [HypothesisSpec] {
        let availability = await provider.availability()
        guard case .available = availability else { return [] }
        let schemaLines: String
        if let rows {
            schemaLines = FeatureCoverageSummary.schemaPromptLines(rows)
        } else {
            schemaLines = (try? PatternEvaluationService(store: store).schemaSummary()) ?? ""
        }
        do {
            let payload = try await provider.generatePatternDiscovery(schemaLines: schemaLines)
            var compiled: [HypothesisSpec] = []
            var seen = Set<String>()
            for hypothesis in payload.hypotheses.prefix(PatternKit.proposeCap) {
                guard let spec = compile(hypothesis) else { continue }
                let id = HypothesisCompiler.canonicalID(for: spec)
                if seen.insert(id).inserted {
                    compiled.append(spec)
                }
            }
            return compiled
        } catch {
            return []
        }
    }

    private static func compile(_ hypothesis: PatternDiscoveryHypothesis) -> HypothesisSpec? {
        guard let exposureField = DayFeatureField(rawValue: hypothesis.exposureField),
              let op = ExposureOp(rawValue: hypothesis.exposureOp),
              let outcomeField = DayFeatureField(rawValue: hypothesis.outcomeField)
        else {
            return nil
        }
        let spec = HypothesisSpec(
            id: hypothesis.id,
            exposure: ExposureSpec(
                field: exposureField,
                op: op,
                band: hypothesis.exposureBand
            ),
            outcome: OutcomeSpec(field: outcomeField),
            lag: hypothesis.lag,
            match: MatchingCriteria(requireTrainingDay: hypothesis.requireTrainingDay)
        )
        switch HypothesisCompiler.compile(spec) {
        case .success(let compiled):
            return compiled
        case .failure:
            return nil
        }
    }
}
