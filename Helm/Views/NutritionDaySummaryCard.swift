import Core
import DesignSystem
import HealthKitIngest
import NutritionKit
import SwiftUI

struct NutritionMacroProgressRow: View {
    let label: String
    let actual: Int?
    let target: Int
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            HStack {
                Text(label)
                    .helmType(.body, color: HelmColor.fgSecondary)
                Spacer()
                Text(valueText)
                    .helmType(.body)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HelmColor.gaugeTrack)
                    Capsule()
                        .fill(HelmColor.color(for: progressState))
                        .frame(width: geometry.size.width * progressFraction)
                }
            }
            .frame(height: 6)
        }
    }

    private var progressFraction: CGFloat {
        guard target > 0, let actual else { return 0 }
        return CGFloat(min(Double(actual) / Double(target), 1.0))
    }

    private var progressState: HelmState {
        guard let actual else { return .compromised }
        let ratio = Double(actual) / Double(target)
        if ratio >= 1.0 { return .primed }
        if ratio < 0.5 { return .depleted }
        return .ready
    }

    private var valueText: String {
        let actualText = actual.map { "\($0)" } ?? "-"
        return "\(actualText) / \(target) \(unit)"
    }
}

struct NutritionAlcoholGapRow: View {
    let gapKilocalories: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("Untracked energy")
                    .helmType(.body)
                Text("Not folded into macro targets")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
            Spacer()
            Text("+\(Int(gapKilocalories.rounded())) kcal")
                .helmType(.monoTag, color: HelmColor.depleted)
        }
        .padding(.vertical, HelmSpacing.xxs)
    }
}

struct NutritionDaySummaryCard: View {
    let snapshot: NutritionDaySnapshot
    var showTrend: Bool = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                header

                NutritionMacroProgressRow(
                    label: "Calories",
                    actual: actualCalories,
                    target: snapshot.targets.caloriesKcal,
                    unit: "kcal"
                )

                NutritionMacroProgressRow(
                    label: "Protein",
                    actual: actualProtein,
                    target: snapshot.targets.proteinGrams,
                    unit: "g"
                )

                NutritionMacroProgressRow(
                    label: "Carbohydrates",
                    actual: actualCarbs,
                    target: snapshot.targets.carbohydrateGrams,
                    unit: "g"
                )

                NutritionMacroProgressRow(
                    label: "Fat",
                    actual: actualFat,
                    target: snapshot.targets.fatGrams,
                    unit: "g"
                )

                if let gap = snapshot.targets.macroGapKilocalories,
                   gap > MacroGapCalculator.significanceThresholdKcal {
                    NutritionAlcoholGapRow(gapKilocalories: gap)
                }

                if showTrend {
                    trendSection
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .helmType(.label)
            Spacer()
            Text(snapshot.dayType.rawValue.capitalized)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        Divider()
            .overlay(HelmColor.gaugeTrack)

        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("TDEE trend")
                .helmType(.label)

            if let tdee = snapshot.trend.estimatedTDEEKcal {
                StatRow(
                    label: "Estimated TDEE",
                    value: "\(Int(tdee.rounded())) kcal",
                    detail: "Adaptive weekly estimate"
                )
            }

            if let intake = snapshot.trend.weeklyIntakeAverageKcal {
                StatRow(
                    label: "7-day intake avg",
                    value: "\(Int(intake.rounded())) kcal"
                )
            }

            if let weight = snapshot.trend.smoothedTrendWeightKg {
                StatRow(
                    label: "Trend weight",
                    value: String(format: "%.1f kg", weight)
                )
            }
        }
    }

    private var actualCalories: Int? {
        snapshot.actual?.totalEnergy.map { Int($0.kilocalories.rounded()) }
    }

    private var actualProtein: Int? {
        snapshot.actual?.totalProteinGrams.map { Int($0.rounded()) }
    }

    private var actualCarbs: Int? {
        snapshot.actual?.totalCarbohydrateGrams.map { Int($0.rounded()) }
    }

    private var actualFat: Int? {
        snapshot.actual?.totalFatGrams.map { Int($0.rounded()) }
    }
}

#Preview {
    let day = HelmDay(year: 2026, month: 7, day: 23)
    let actual = NutritionDay(
        helmDay: day,
        totalEnergy: Energy(kilocalories: 1_800),
        totalProteinGrams: 140,
        totalCarbohydrateGrams: 180,
        totalFatGrams: 55,
        macroGapKilocalories: 320
    )
    let targets = MacroTargets(
        caloriesKcal: 2_400,
        proteinGrams: 160,
        carbohydrateGrams: 280,
        fatGrams: 70,
        dayType: .training,
        estimatedTDEEKcal: 2_640,
        macroGapKilocalories: 320
    )
    let snapshot = NutritionDaySnapshot(
        helmDay: day,
        targets: targets,
        actual: actual,
        trend: NutritionTrendState(estimatedTDEEKcal: 2_640, weeklyIntakeAverageKcal: 2_100),
        dayType: .training,
        phase: .maintain
    )

    ScrollView {
        NutritionDaySummaryCard(snapshot: snapshot, showTrend: true)
            .padding()
    }
    .helmTheme()
}
