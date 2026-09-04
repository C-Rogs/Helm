import Foundation

public struct FeatureCoverage: Sendable, Equatable {
    public var field: DayFeatureField
    public var nonMissing: Int
    public var total: Int

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(nonMissing) / Double(total)
    }
}

public enum FeatureCoverageSummary {
    public static func summarize(_ rows: [DayFeatureRow]) -> [FeatureCoverage] {
        DayFeatureField.allCases.map { field in
            let nonMissing = rows.filter { !$0.isMissing(field) }.count
            return FeatureCoverage(field: field, nonMissing: nonMissing, total: rows.count)
        }
    }

    public static func schemaPromptLines(_ rows: [DayFeatureRow]) -> String {
        let lines = summarize(rows).map { item in
            "\(item.field.rawValue) kind=\(item.field.kind.rawValue) n=\(item.nonMissing)/\(item.total)"
        }
        return lines.joined(separator: "\n")
    }
}

public enum TypedHypothesisSearch {
    public static func candidates(
        rows: [DayFeatureRow],
        existingIDs: Set<String>,
        budget: Int = PatternKit.typedSearchBudget
    ) -> [HypothesisSpec] {
        let coverage = Dictionary(
            uniqueKeysWithValues: FeatureCoverageSummary.summarize(rows).map { ($0.field, $0) }
        )
        let exposures: [(DayFeatureField, ExposureOp, String?)] = DayFeatureField.allCases.flatMap { field -> [(DayFeatureField, ExposureOp, String?)] in
            switch field.kind {
            case .binary:
                return [(field, .present, nil)]
            case .continuous:
                return [(field, .tertileLow, nil), (field, .tertileHigh, nil)]
            case .residual:
                return [(field, .residualPositive, nil)]
            case .categorical:
                if field == .dayDemand {
                    return [(field, .bandEquals, "office")]
                }
                if field == .arcBand {
                    return [(field, .bandEquals, "depleted"), (field, .bandEquals, "primed")]
                }
                return []
            }
        }
        let outcomes = DayFeatureField.allCases.filter {
            $0.kind == .continuous || $0.kind == .residual
        }
        var scored: [(Double, HypothesisSpec)] = []
        for (field, op, band) in exposures {
            let expN = coverage[field]?.nonMissing ?? 0
            guard expN >= PatternKit.minArmCount else { continue }
            for outcome in outcomes where outcome != field {
                let outN = coverage[outcome]?.nonMissing ?? 0
                guard outN >= PatternKit.minArmCount else { continue }
                for lag in 0 ... 1 {
                    let spec = HypothesisSpec(
                        id: "search_\(field.rawValue)_\(op.rawValue)_\(band ?? "")_\(outcome.rawValue)_lag\(lag)",
                        exposure: ExposureSpec(field: field, op: op, band: band),
                        outcome: OutcomeSpec(field: outcome),
                        lag: lag
                    )
                    let key = HypothesisCompiler.astKey(spec)
                    guard !existingIDs.contains(spec.id), !existingIDs.contains(key) else { continue }
                    if TautologyFilter.shouldSuppress(spec) { continue }
                    if HypothesisCompiler.compile(spec).isFailure { continue }
                    let score = Double(min(expN, outN)) / (1.0 + Double(lag))
                    scored.append((score, spec))
                }
            }
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(budget).map(\.1)
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
