import Foundation

public enum ContrastEngine {
    public static func evaluate(
        rows: [DayFeatureRow],
        spec: HypothesisSpec,
        permutationCap: Int = PatternKit.permutationCap
    ) -> ContrastResult {
        switch HypothesisCompiler.compile(spec) {
        case .failure(let error):
            return ContrastResult(
                spec: spec,
                nExp: 0,
                nCtrl: 0,
                verdict: .killSample,
                notes: "compile: \(error)"
            )
        case .success:
            break
        }

        if TautologyFilter.shouldSuppress(spec) {
            return ContrastResult(
                spec: spec,
                nExp: 0,
                nCtrl: 0,
                verdict: .suppress,
                notes: "tautology"
            )
        }

        let ordered = rows.sorted { $0.helmDay < $1.helmDay }
        guard !ordered.isEmpty else {
            return ContrastResult(spec: spec, nExp: 0, nCtrl: 0, verdict: .killSample, notes: "empty matrix")
        }

        let labels = exposureLabels(rows: ordered, spec: spec)
        let outcomes = alignedOutcomes(rows: ordered, spec: spec)
        var eligibleExp: [Double] = []
        var eligibleCtrl: [Double] = []
        for i in ordered.indices {
            guard let label = labels[i], let y = outcomes[i] else { continue }
            if label {
                eligibleExp.append(y)
            } else {
                eligibleCtrl.append(y)
            }
        }

        let nExp = eligibleExp.count
        let nCtrl = eligibleCtrl.count
        let medianExp = CliffsDelta.median(eligibleExp)
        let medianCtrl = CliffsDelta.median(eligibleCtrl)
        let medianDelta = zipOptional(medianExp, medianCtrl).map { $0 - $1 }

        let priorUpdate = posterior(spec: spec, sampleMean: medianDelta, n: nExp)

        guard nExp >= PatternKit.minArmCount, nCtrl >= PatternKit.minArmCount else {
            return ContrastResult(
                spec: spec,
                nExp: nExp,
                nCtrl: nCtrl,
                medianExp: medianExp,
                medianCtrl: medianCtrl,
                medianDelta: medianDelta,
                posteriorMu: priorUpdate?.mu,
                posteriorSigma: priorUpdate?.sigma,
                verdict: .killSample,
                notes: "min arm \(PatternKit.minArmCount)"
            )
        }

        guard let cliffs = CliffsDelta.estimate(exposure: eligibleExp, control: eligibleCtrl) else {
            return ContrastResult(
                spec: spec,
                nExp: nExp,
                nCtrl: nCtrl,
                medianExp: medianExp,
                medianCtrl: medianCtrl,
                medianDelta: medianDelta,
                posteriorMu: priorUpdate?.mu,
                posteriorSigma: priorUpdate?.sigma,
                verdict: .killSample,
                notes: "delta undefined"
            )
        }

        let permutationP = cyclicShiftP(
            labels: labels,
            outcomes: outcomes,
            observedAbs: abs(cliffs.delta),
            cap: permutationCap
        )

        let eValue = MeanDifferenceEProcess.eValue(
            exposure: eligibleExp,
            control: eligibleCtrl
        )

        var verdict: ContrastVerdict = .killNull
        if spec.copyRegisterHint == .softContext, abs(cliffs.delta) >= PatternKit.minAbsDelta {
            verdict = .soft
        } else if abs(cliffs.delta) >= PatternKit.minAbsDelta,
                  (permutationP ?? 1) <= PatternKit.permutationAlpha {
            verdict = .ship
        } else if abs(cliffs.delta) < PatternKit.retireAbsDelta {
            verdict = .killNull
        } else {
            verdict = .killNull
        }

        return ContrastResult(
            spec: spec,
            nExp: nExp,
            nCtrl: nCtrl,
            medianExp: medianExp,
            medianCtrl: medianCtrl,
            medianDelta: medianDelta,
            cliffs: cliffs,
            permutationP: permutationP,
            posteriorMu: priorUpdate?.mu,
            posteriorSigma: priorUpdate?.sigma,
            eValue: eValue,
            verdict: verdict
        )
    }

    public static func evaluateCatalog(
        rows: [DayFeatureRow],
        specs: [HypothesisSpec],
        previous: [String: PatternFinding] = [:],
        now: Date = Date(),
        sequentialFDR: LORDPlusPlusState? = nil
    ) -> (findings: [PatternFinding], fdrState: LORDPlusPlusState?) {
        var results = specs.map { evaluate(rows: rows, spec: $0) }
        let qValues = BenjaminiHochberg.qValues(results.map(\.permutationP))
        for i in results.indices {
            results[i].fdrQ = qValues[i]
            if results[i].verdict == .ship,
               let q = qValues[i],
               q > PatternKit.fdrQ,
               results[i].spec.copyRegisterHint != .softContext {
                results[i].verdict = .killNull
                results[i].notes = "BH q=\(q)"
            }
        }

        var fdrState = sequentialFDR
        if var state = fdrState {
            for i in results.indices {
                let id = HypothesisCompiler.canonicalID(for: results[i].spec)
                guard results[i].permutationP != nil, previous[id] == nil else { continue }
                let spend = state.spend(p: results[i].permutationP ?? 1, id: id)
                if !spend.rejected,
                   results[i].verdict == .ship,
                   results[i].spec.copyRegisterHint != .softContext {
                    results[i].verdict = .killNull
                    results[i].notes = "LORD++"
                }
            }
            fdrState = state
        }

        let findings = results.map { result in
            finding(from: result, previous: previous, now: now)
        }
        return (findings, fdrState)
    }

    private static func finding(
        from result: ContrastResult,
        previous: [String: PatternFinding],
        now: Date
    ) -> PatternFinding {
        let id = HypothesisCompiler.canonicalID(for: result.spec)
        let priorFinding = previous[id]
        let anytimeStable = anytimeStableGate(result)
        let status = FindingLifecycle.status(
            nExp: result.nExp,
            nCtrl: result.nCtrl,
            cliffsDelta: result.cliffs?.delta,
            ciLow: result.cliffs?.ciLow,
            ciHigh: result.cliffs?.ciHigh,
            permutationP: result.permutationP,
            fdrQ: result.fdrQ,
            verdict: result.verdict,
            hasPrior: result.spec.prior != nil,
            previous: priorFinding?.status,
            eValue: result.eValue,
            anytimeStable: anytimeStable
        )
        return PatternFinding(
            id: id,
            spec: result.spec,
            status: status,
            verdict: result.verdict,
            nExp: result.nExp,
            nCtrl: result.nCtrl,
            cliffsDelta: result.cliffs?.delta,
            medianDelta: result.medianDelta,
            permutationP: result.permutationP,
            fdrQ: result.fdrQ,
            ciLow: result.cliffs?.ciLow,
            ciHigh: result.cliffs?.ciHigh,
            copyRegister: FindingCopy.register(
                status: status,
                hint: result.spec.copyRegisterHint,
                verdict: result.verdict
            ),
            headline: FindingCopy.headline(
                for: result.spec,
                status: status,
                medianDelta: result.medianDelta
            ),
            body: FindingCopy.body(
                spec: result.spec,
                status: status,
                nExp: result.nExp,
                nCtrl: result.nCtrl,
                medianDelta: result.medianDelta,
                cliffsDelta: result.cliffs?.delta,
                unitHint: result.spec.prior?.unit
            ),
            firstDetectedAt: priorFinding?.firstDetectedAt ?? now,
            updatedAt: now,
            posteriorMu: result.posteriorMu,
            posteriorSigma: result.posteriorSigma,
            eValue: result.eValue
        )
    }

    private static func anytimeStableGate(_ result: ContrastResult) -> Bool {
        guard let e = result.eValue, e >= 1.0 / PatternKit.permutationAlpha else { return false }
        guard min(result.nExp, result.nCtrl) >= PatternKit.minArmCount else { return false }
        guard let delta = result.cliffs?.delta, abs(delta) >= PatternKit.minAbsDelta else { return false }
        return true
    }

    // MARK: - Alignment

    static func exposureLabels(rows: [DayFeatureRow], spec: HypothesisSpec) -> [Bool?] {
        let matchMask = matchEligibility(rows: rows, spec: spec)
        let outcomeReady = rows.indices.map { index -> Bool in
            let lagged = index + spec.lag
            guard lagged < rows.count else { return false }
            return !rows[lagged].isMissing(spec.outcome.field)
        }

        switch spec.exposure.op {
        case .present, .absent:
            return rows.enumerated().map { index, row in
                guard matchMask[index], outcomeReady[index], let flag = row.binary(spec.exposure.field) else {
                    return nil
                }
                return spec.exposure.op == .present ? flag : !flag
            }
        case .bandEquals:
            let band = spec.exposure.band ?? ""
            return rows.enumerated().map { index, row in
                guard matchMask[index], outcomeReady[index], let value = row.categorical(spec.exposure.field) else {
                    return nil
                }
                return value == band
            }
        case .residualPositive, .residualNonPositive:
            return rows.enumerated().map { index, row in
                guard matchMask[index], outcomeReady[index], let value = row.continuous(spec.exposure.field) else {
                    return nil
                }
                return spec.exposure.op == .residualPositive ? value > 0 : value <= 0
            }
        case .tertileLow, .tertileHigh:
            let values = rows.enumerated().compactMap { index, row -> (Int, Double)? in
                guard matchMask[index], outcomeReady[index], let value = row.continuous(spec.exposure.field) else {
                    return nil
                }
                return (index, value)
            }
            let cuts = tertileCuts(values.map(\.1))
            var labels = Array(repeating: Optional<Bool>.none, count: rows.count)
            guard let cuts else { return labels }
            for (index, value) in values {
                if spec.exposure.op == .tertileLow {
                    labels[index] = value <= cuts.low
                } else {
                    labels[index] = value >= cuts.high
                }
            }
            return labels
        }
    }

    static func alignedOutcomes(rows: [DayFeatureRow], spec: HypothesisSpec) -> [Double?] {
        rows.indices.map { index in
            let lagged = index + spec.lag
            guard lagged < rows.count else { return nil }
            return rows[lagged].continuous(spec.outcome.field)
        }
    }

    static func matchEligibility(rows: [DayFeatureRow], spec: HypothesisSpec) -> [Bool] {
        var mask = rows.map { row in
            if spec.match.requireTrainingDay {
                return row.trainingDay == true
            }
            return true
        }
        if spec.match.sameWeekdayAsExposure {
            let exposureWeekdays = Set(
                zip(rows, mask).compactMap { row, eligible -> Int? in
                    guard eligible else { return nil }
                    if let flag = row.binary(spec.exposure.field), flag { return row.weekday }
                    if spec.exposure.op == .bandEquals, row.categorical(spec.exposure.field) == spec.exposure.band {
                        return row.weekday
                    }
                    return nil
                }
            )
            if !exposureWeekdays.isEmpty {
                for i in rows.indices where mask[i] {
                    mask[i] = exposureWeekdays.contains(rows[i].weekday)
                }
            }
        }
        return mask
    }

    static func tertileCuts(_ values: [Double]) -> (low: Double, high: Double)? {
        guard values.count >= 3 else { return nil }
        let sorted = values.sorted()
        let lowIndex = max(0, Int((Double(sorted.count - 1) / 3.0).rounded(.down)))
        let highIndex = min(sorted.count - 1, Int((2.0 * Double(sorted.count - 1) / 3.0).rounded(.up)))
        return (sorted[lowIndex], sorted[highIndex])
    }

    static func cyclicShiftP(
        labels: [Bool?],
        outcomes: [Double?],
        observedAbs: Double,
        cap: Int
    ) -> Double? {
        let n = outcomes.count
        guard n > 2 else { return nil }
        let shifts = min(n - 1, cap)
        guard shifts > 0 else { return nil }
        var count = 0
        for s in 1 ... shifts {
            var shiftedExp: [Double] = []
            var shiftedCtrl: [Double] = []
            for i in 0 ..< n {
                guard let label = labels[i] else { continue }
                let source = (i + s) % n
                guard let y = outcomes[source] else { continue }
                if label {
                    shiftedExp.append(y)
                } else {
                    shiftedCtrl.append(y)
                }
            }
            guard shiftedExp.count >= PatternKit.minArmCount,
                  shiftedCtrl.count >= PatternKit.minArmCount,
                  let delta = CliffsDelta.estimate(exposure: shiftedExp, control: shiftedCtrl)?.delta
            else { continue }
            if abs(delta) >= observedAbs - 1e-12 {
                count += 1
            }
        }
        return (Double(count) + 1) / (Double(shifts) + 1)
    }

    private static func posterior(
        spec: HypothesisSpec,
        sampleMean: Double?,
        n: Int
    ) -> (mu: Double, sigma: Double)? {
        guard let prior = spec.prior, let sampleMean, n > 0 else {
            if let prior = spec.prior {
                return (prior.mu0, prior.sigma0)
            }
            return nil
        }
        return BayesMeanDifference.posterior(
            mu0: prior.mu0,
            sigma0: prior.sigma0,
            sampleMean: sampleMean,
            sampleSigma: prior.sigma0,
            n: n
        )
    }

    private static func zipOptional(_ a: Double?, _ b: Double?) -> (Double, Double)? {
        guard let a, let b else { return nil }
        return (a, b)
    }

}
