import Foundation
import Testing
@testable import PatternKit
import Core

@Suite("Cliff's delta")
struct CliffsDeltaTests {
    @Test("complete dominance is plus one")
    func completeDominance() {
        let estimate = CliffsDelta.estimate(exposure: [10, 11, 12], control: [1, 2, 3])
        #expect(estimate?.delta == 1)
    }

    @Test("identical samples are zero")
    func identical() {
        let estimate = CliffsDelta.estimate(exposure: [1, 2, 3], control: [1, 2, 3])
        #expect(abs(estimate?.delta ?? 99) < 1e-9)
    }

    @Test("complete reverse dominance is minus one")
    func reverseDominance() {
        let estimate = CliffsDelta.estimate(exposure: [1, 2, 3], control: [10, 11, 12])
        #expect(estimate?.delta == -1)
    }
}

@Suite("Hypothesis compiler")
struct HypothesisCompilerTests {
    @Test("rejects lag above max")
    func lagOutOfRange() {
        let spec = HypothesisSpec(
            id: "bad_lag",
            exposure: ExposureSpec(field: .alcohol, op: .present),
            outcome: OutcomeSpec(field: .restingHr),
            lag: 9
        )
        #expect(HypothesisCompiler.compile(spec) == .failure(.lagOutOfRange(9)))
    }

    @Test("rejects tertile on binary")
    func illegalOp() {
        let spec = HypothesisSpec(
            id: "bad_op",
            exposure: ExposureSpec(field: .alcohol, op: .tertileHigh),
            outcome: OutcomeSpec(field: .restingHr),
            lag: 0
        )
        if case .failure(.illegalOpForField) = HypothesisCompiler.compile(spec) {
            // ok
        } else {
            Issue.record("expected illegal op")
        }
    }
}

@Suite("Tautology filter")
struct TautologyFilterTests {
    @Test("low HRV to raw workout minutes is suppressed")
    func hrvToMinutes() {
        let spec = HypothesisSpec(
            id: "low_hrv_fewer_workout_min",
            exposure: ExposureSpec(field: .hrvSdnn, op: .tertileLow),
            outcome: OutcomeSpec(field: .workoutMinutes),
            lag: 0
        )
        #expect(TautologyFilter.shouldSuppress(spec))
        let result = ContrastEngine.evaluate(rows: [], spec: spec)
        #expect(result.verdict == .suppress)
    }

    @Test("alcohol to resting HR is allowed")
    func alcoholToRHR() {
        let spec = HypothesisSpec(
            id: "alcohol_rhr",
            exposure: ExposureSpec(field: .alcohol, op: .present),
            outcome: OutcomeSpec(field: .restingHr),
            lag: 1
        )
        #expect(!TautologyFilter.shouldSuppress(spec))
    }
}

@Suite("Contrast engine")
struct ContrastEngineTests {
    @Test("alcohol lag 1 uses next-night sleep not same-day")
    func alcoholSleepLag() {
        var rows: [DayFeatureRow] = []
        let start = HelmDay(year: 2026, month: 1, day: 1)
        for i in 0 ..< 55 {
            let alcohol = i < 20
            rows.append(
                DayFeatureRow(
                    helmDay: start.adding(days: i),
                    alcohol: alcohol,
                    sleepAsleepMin: 420
                )
            )
        }
        for i in 0 ..< 20 {
            rows[i + 1].sleepAsleepMin = 240
        }
        for i in 21 ..< 55 {
            rows[i].sleepAsleepMin = 420
        }
        let spec = HypothesisSpec(
            id: "alcohol_worse_sleep",
            exposure: ExposureSpec(field: .alcohol, op: .present),
            outcome: OutcomeSpec(field: .sleepAsleepMin),
            lag: 1
        )
        let result = ContrastEngine.evaluate(rows: rows, spec: spec, permutationCap: 80)
        #expect(result.nExp >= 12)
        #expect(result.medianDelta ?? 0 < -50)
        #expect((result.cliffs?.delta ?? 0) < -0.4)
    }

    @Test("low sleep to next RHR ships on a strong synthetic series")
    func lowSleepNextRHR() {
        var rows: [DayFeatureRow] = []
        let start = HelmDay(year: 2026, month: 1, day: 1)
        for i in 0 ..< 80 {
            let sleep: Double = i < 30 ? 260 : 480
            rows.append(
                DayFeatureRow(
                    helmDay: start.adding(days: i),
                    sleepAsleepMin: sleep,
                    restingHr: 60
                )
            )
        }
        for i in 1 ..< rows.count {
            let priorSleep = rows[i - 1].sleepAsleepMin ?? 400
            rows[i].restingHr = priorSleep < 320 ? 72 : 56
        }
        let spec = SeedCatalog.all.first { $0.id == "low_sleep_higher_rhr" }!
        let result = ContrastEngine.evaluate(rows: rows, spec: spec, permutationCap: 80)
        #expect(result.nExp >= 12)
        #expect(result.nCtrl >= 12)
        #expect((result.cliffs?.delta ?? 0) > 0.15)
        #expect(result.verdict == .ship)
    }

    @Test("N=2 alcohol is kill_sample")
    func alcoholKillSample() {
        var rows: [DayFeatureRow] = []
        let start = HelmDay(year: 2026, month: 1, day: 1)
        for i in 0 ..< 40 {
            rows.append(
                DayFeatureRow(
                    helmDay: start.adding(days: i),
                    alcohol: i < 2,
                    dietEnergyKcal: 2200
                )
            )
        }
        let spec = SeedCatalog.all.first { $0.id == "alcohol_lower_kcal" }!
        let result = ContrastEngine.evaluate(rows: rows, spec: spec)
        #expect(result.verdict == .killSample)
        #expect(result.nExp == 2)
    }

    @Test("catalog alcohol N=2 stays prior_seed")
    func catalogAlcoholPriorSeed() {
        var rows: [DayFeatureRow] = []
        let start = HelmDay(year: 2026, month: 1, day: 1)
        for i in 0 ..< 40 {
            rows.append(
                DayFeatureRow(
                    helmDay: start.adding(days: i),
                    alcohol: i < 2,
                    dietEnergyKcal: 2200
                )
            )
        }
        let spec = SeedCatalog.all.first { $0.id == "alcohol_lower_kcal" }!
        let (findings, _) = ContrastEngine.evaluateCatalog(rows: rows, specs: [spec])
        #expect(findings.first?.status == .priorSeed)
        #expect(findings.first?.copyRegister == .educational)
    }

    @Test("diet zero is missing so it does not enter tertiles")
    func dietZeroMissing() {
        #expect(DayFeatureMissingness.dietValue(0) == nil)
        #expect(DayFeatureMissingness.dietValue(-1) == nil)
        #expect(DayFeatureMissingness.dietValue(1800) == 1800)
    }
}

@Suite("Cyclic shift size")
struct CyclicShiftSizeTests {
    @Test("AR1 true-null cyclic shift stays near nominal size")
    func ar1FalsePositive() {
        var rng = SplitMix64(seed: 42)
        var rejections = 0
        let trials = 24
        for _ in 0 ..< trials {
            let rows = makeAR1Rows(n: 120, phi: 0.7, rng: &rng)
            let spec = HypothesisSpec(
                id: "null_binary_rhr",
                exposure: ExposureSpec(field: .alcohol, op: .present),
                outcome: OutcomeSpec(field: .restingHr),
                lag: 0
            )
            let result = ContrastEngine.evaluate(rows: rows, spec: spec, permutationCap: 60)
            if result.verdict == .ship {
                rejections += 1
            }
        }
        #expect(rejections <= 6)
    }
}

@Suite("Online FDR and e-process")
struct SequentialInferenceTests {
    @Test("LORD gamma sums toward one")
    func gammaSum() {
        var sum = 0.0
        for t in 1 ... 500 {
            sum += LORDPlusPlusState.gamma(t)
        }
        #expect(abs(sum - 1) < 0.02)
    }

    @Test("Ville bound smoke: null e-values rarely exceed 1/alpha")
    func villeSmoke() {
        var rng = SplitMix64(seed: 7)
        var exceed = 0
        let paths = 40
        let alpha = 0.05
        for _ in 0 ..< paths {
            var exp: [Double] = []
            var ctrl: [Double] = []
            var hit = false
            for _ in 0 ..< 40 {
                exp.append(rng.nextGaussian())
                ctrl.append(rng.nextGaussian())
                if let e = MeanDifferenceEProcess.eValue(exposure: exp, control: ctrl), e >= 1 / alpha {
                    hit = true
                }
            }
            if hit { exceed += 1 }
        }
        #expect(exceed <= 8)
    }

    @Test("LORD does not re-spend alpha on the same AST id")
    func lordNoRespend() {
        var state = LORDPlusPlusState()
        let first = state.spend(p: 0.001, id: "search_alcohol_rhr")
        #expect(first.rejected)
        let second = state.spend(p: 0.001, id: "search_alcohol_rhr")
        #expect(second.alpha == 0)
        #expect(state.testIndex == 1)
    }

    @Test("SAFFRON skips likely nulls above lambda")
    func saffronSkip() {
        var state = SaffronState()
        let skipped = state.spend(p: 0.9)
        #expect(!skipped.rejected)
        #expect(state.candidates == 0)
        let hit = state.spend(p: 0.001)
        #expect(hit.rejected)
        #expect(state.rejections == 1)
    }
}

@Suite("Finding copy")
struct FindingCopyTests {
    @Test("stable headline uses median direction")
    func directedStable() {
        let spec = SeedCatalog.all.first { $0.id == "alcohol_worse_sleep" }!
        let lower = FindingCopy.headline(for: spec, status: .stable, medianDelta: -18)
        #expect(lower.contains("lower"))
        let higher = FindingCopy.headline(for: spec, status: .stable, medianDelta: 12)
        #expect(higher.contains("higher"))
    }

    @Test("alcohol sleep prior unit is minutes")
    func alcoholSleepUnit() {
        let spec = SeedCatalog.all.first { $0.id == "alcohol_worse_sleep" }!
        #expect(spec.prior?.unit == "min")
        let body = FindingCopy.body(
            spec: spec,
            status: .emerging,
            nExp: 14,
            nCtrl: 22,
            medianDelta: -18,
            cliffsDelta: -0.4,
            unitHint: spec.prior?.unit
        )
        #expect(body.contains("min"))
        #expect(!body.contains("Cliff"))
    }
}

@Suite("Analogous days")
struct AnalogousDayEngineTests {
    @Test("near neighbors beat a far outlier")
    func nearNeighbors() {
        var rows: [DayFeatureRow] = []
        let start = HelmDay(year: 2026, month: 2, day: 1)
        for i in 0 ..< 20 {
            rows.append(
                DayFeatureRow(
                    helmDay: start.adding(days: i),
                    dietEnergyKcal: 2000,
                    dietProteinG: 140,
                    sleepAsleepMin: 420,
                    hrvSdnn: 50,
                    restingHr: 58,
                    workoutMinutes: 40
                )
            )
        }
        rows.append(
            DayFeatureRow(
                helmDay: start.adding(days: 20),
                dietEnergyKcal: 4200,
                dietProteinG: 40,
                sleepAsleepMin: 180,
                hrvSdnn: 20,
                restingHr: 80,
                workoutMinutes: 0
            )
        )
        let neighbors = AnalogousDayEngine.neighbors(of: rows[10], in: rows, k: 5)
        #expect(!neighbors.isEmpty)
        #expect(neighbors.first?.distance ?? 99 < AnalogousDayEngine.nearThreshold)
        #expect(!neighbors.contains { $0.helmDay == start.adding(days: 20) })
    }
}

private struct SplitMix64 {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func nextGaussian() -> Double {
        let u1 = max(nextDouble(), 1e-12)
        let u2 = nextDouble()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

private func makeAR1Rows(n: Int, phi: Double, rng: inout SplitMix64) -> [DayFeatureRow] {
    var rows: [DayFeatureRow] = []
    let start = HelmDay(year: 2025, month: 1, day: 1)
    var y = rng.nextGaussian()
    for i in 0 ..< n {
        y = phi * y + rng.nextGaussian()
        rows.append(
            DayFeatureRow(
                helmDay: start.adding(days: i),
                alcohol: rng.nextDouble() < 0.35,
                restingHr: 60 + y
            )
        )
    }
    return rows
}
