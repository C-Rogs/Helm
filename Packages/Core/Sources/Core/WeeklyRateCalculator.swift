import Foundation

public enum WeeklyRateCalculator: Sendable {
    public struct Input: Sendable, Equatable {
        public let currentWeightKg: Double
        public let targetWeightKg: Double
        public let targetDate: Date
        public let referenceDate: Date

        public init(
            currentWeightKg: Double,
            targetWeightKg: Double,
            targetDate: Date,
            referenceDate: Date
        ) {
            self.currentWeightKg = currentWeightKg
            self.targetWeightKg = targetWeightKg
            self.targetDate = targetDate
            self.referenceDate = referenceDate
        }
    }

    public struct Result: Sendable, Equatable {
        public let weeklyRateKg: Double
        public let weeksRemaining: Double
        public let phase: TrainingPhase

        public init(weeklyRateKg: Double, weeksRemaining: Double, phase: TrainingPhase) {
            self.weeklyRateKg = weeklyRateKg
            self.weeksRemaining = weeksRemaining
            self.phase = phase
        }
    }

    public static func calculate(_ input: Input, calendar: Calendar = .current) -> Result? {
        guard input.currentWeightKg > 0, input.targetWeightKg > 0 else { return nil }
        let dayDelta = calendar.dateComponents([.day], from: input.referenceDate, to: input.targetDate).day ?? 0
        guard dayDelta > 0 else { return nil }

        let weeks = Double(dayDelta) / 7.0
        let delta = input.targetWeightKg - input.currentWeightKg
        let weeklyRate = delta / weeks
        let phase: TrainingPhase
        if abs(delta) < 0.05 {
            phase = .maintain
        } else if delta < 0 {
            phase = .cut
        } else {
            phase = .gain
        }
        return Result(weeklyRateKg: abs(weeklyRate), weeksRemaining: weeks, phase: phase)
    }

    public static func safeRangeHint(for phase: TrainingPhase) -> String {
        switch phase {
        case .cut:
            "Typical cut: 0.25 to 0.75 kg per week."
        case .gain:
            "Typical gain: 0.1 to 0.35 kg per week."
        case .maintain:
            "Maintain keeps weight steady."
        }
    }
}
