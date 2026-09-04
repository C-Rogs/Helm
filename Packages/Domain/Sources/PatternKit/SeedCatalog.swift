import Foundation

public enum SeedCatalog {
    public static let all: [HypothesisSpec] = [
        HypothesisSpec(
            id: "low_sleep_higher_rhr",
            exposure: ExposureSpec(field: .sleepAsleepMin, op: .tertileLow),
            outcome: OutcomeSpec(field: .restingHr),
            lag: 1,
            copyRegisterHint: .confirmed,
            prior: LiteraturePrior(
                mu0: 2.0,
                sigma0: 0.8,
                unit: "bpm",
                educationalCopy: "Shorter sleep is linked with higher next-day resting heart rate in clinical samples.",
                minNToUpdate: 0
            )
        ),
        HypothesisSpec(
            id: "low_sleep_lower_hrv",
            exposure: ExposureSpec(field: .sleepAsleepMin, op: .tertileLow),
            outcome: OutcomeSpec(field: .hrvSdnn),
            lag: 1,
            copyRegisterHint: .confirmed
        ),
        HypothesisSpec(
            id: "high_kcal_next_weight_up",
            exposure: ExposureSpec(field: .dietEnergyKcal, op: .tertileHigh),
            outcome: OutcomeSpec(field: .bodyMassKg),
            lag: 1,
            copyRegisterHint: .softContext,
            prior: LiteraturePrior(
                mu0: 0.8,
                sigma0: 0.3,
                unit: "kg",
                educationalCopy: "A high-energy day often raises next-morning scale weight via glycogen and water, not fat.",
                minNToUpdate: 0
            )
        ),
        HypothesisSpec(
            id: "alcohol_lower_kcal",
            exposure: ExposureSpec(field: .alcohol, op: .present),
            outcome: OutcomeSpec(field: .dietEnergyKcal),
            lag: 0,
            copyRegisterHint: .educational,
            prior: LiteraturePrior(
                mu0: 0,
                sigma0: 200,
                unit: "kcal",
                educationalCopy: "Log drinks to see whether alcohol days change your energy intake.",
                minNToUpdate: 5
            )
        ),
        HypothesisSpec(
            id: "alcohol_worse_sleep",
            exposure: ExposureSpec(field: .alcohol, op: .present),
            outcome: OutcomeSpec(field: .sleepAsleepMin),
            lag: 1,
            copyRegisterHint: .educational,
            prior: LiteraturePrior(
                mu0: -25,
                sigma0: 8,
                unit: "min",
                educationalCopy: "Clinical research shows acute alcohol often fragments sleep and can raise nighttime heart rate. Log drinks to measure your response.",
                minNToUpdate: 5
            )
        ),
        HypothesisSpec(
            id: "office_volume_residual",
            exposure: ExposureSpec(field: .dayDemand, op: .bandEquals, band: "office"),
            outcome: OutcomeSpec(field: .volumeResidual),
            lag: 0,
            match: .trainingDay,
            copyRegisterHint: .tentative
        )
    ]
}

public enum BayesMeanDifference {
    public static func posterior(
        mu0: Double,
        sigma0: Double,
        sampleMean: Double,
        sampleSigma: Double,
        n: Int
    ) -> (mu: Double, sigma: Double) {
        let prec0 = 1 / max(sigma0 * sigma0, 1e-12)
        let prec = Double(max(n, 1)) / max(sampleSigma * sampleSigma, 1e-12)
        let mu = (prec0 * mu0 + prec * sampleMean) / (prec0 + prec)
        let sigma = sqrt(1 / (prec0 + prec))
        return (mu, sigma)
    }
}
