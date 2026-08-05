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
                    .helmNumericRoll(value: valueText)
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
            .frame(height: HelmLayout.progressTrackHeight)
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
        guard target > 0 else {
            if let actual {
                return "\(actual) \(unit) logged"
            }
            return "Target pending"
        }
        let actualText = actual.map { "\($0)" } ?? "-"
        return "\(actualText) / \(target) \(unit)"
    }
}

struct NutritionAlcoholGapRow: View {
    let gapKilocalories: Double
    var onExplain: (() -> Void)?

    var body: some View {
        Button {
            onExplain?()
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text("Untracked energy")
                        .helmType(.body)
                    Text("Energy logged without full macros. Tap to learn more.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
                    Text("+")
                        .helmType(.monoTag, color: HelmColor.depleted)
                    HelmNumericText(Int(gapKilocalories.rounded()))
                        .helmType(.monoTag, color: HelmColor.depleted)
                    Text("kcal")
                        .helmType(.monoTag, color: HelmColor.depleted)
                }
            }
            .padding(.vertical, HelmSpacing.xxs)
        }
        .buttonStyle(.plain)
        .disabled(onExplain == nil)
    }
}

struct NutritionDaySummaryCard: View {
    let snapshot: NutritionDaySnapshot
    var showTrend: Bool = false
    var explainMetric: ExplainableMetric?
    var onAskCoach: ((String) -> Void)?

    @State private var isShowingUntrackedExplain = false
    @State private var isShowingTargetExplain = false

    private var targets: MacroTargets {
        snapshot.targets
    }

    private var hasCalculatedTargets: Bool {
        snapshot.targets.caloriesKcal > 0 && snapshot.targets.proteinGrams > 0
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                header

                if hasCalculatedTargets {
                    NutritionEnergyBalanceSection(balance: snapshot.energyBalance)
                }

                calorieRow

                if hasCalculatedTargets {
                    energyBalanceCaption
                }

                NutritionMacroProgressRow(
                    label: "Protein",
                    actual: actualProtein,
                    target: targets.proteinGrams,
                    unit: "g"
                )

                NutritionMacroProgressRow(
                    label: "Carbohydrates",
                    actual: actualCarbs,
                    target: targets.carbohydrateGrams,
                    unit: "g"
                )

                NutritionMacroProgressRow(
                    label: "Fat",
                    actual: actualFat,
                    target: targets.fatGrams,
                    unit: "g"
                )

                if let gap = targets.macroGapKilocalories,
                   gap > MacroGapCalculator.significanceThresholdKcal {
                    NutritionAlcoholGapRow(gapKilocalories: gap) {
                        isShowingUntrackedExplain = true
                    }
                }

                if showTrend {
                    trendSection
                }
            }
        }
        .sheet(isPresented: $isShowingUntrackedExplain) {
            if let explainMetric, let onAskCoach {
                ExplainSheet(metric: explainMetric, onAskCoach: onAskCoach)
            }
        }
        .sheet(isPresented: $isShowingTargetExplain) {
            if let explainMetric, let onAskCoach {
                ExplainSheet(metric: explainMetric, onAskCoach: onAskCoach)
            }
        }
    }

    private var calorieRow: some View {
        NutritionMacroProgressRow(
            label: "Calories",
            actual: actualCalories,
            target: effectiveCalorieTarget,
            unit: "kcal"
        )
    }

    private var effectiveCalorieTarget: Int {
        snapshot.energyBalance.adjustedTargetKcal ?? targets.caloriesKcal
    }

    @ViewBuilder
    private var energyBalanceCaption: some View {
        switch snapshot.activeEnergyFreshness {
        case let .fresh(burned):
            if let adjusted = snapshot.energyBalance.adjustedTargetKcal {
                Text("\(targets.caloriesKcal) base · \(adjusted) with +\(burned) burned")
                    .helmType(.body, color: HelmColor.fgMuted)
            } else {
                Text(targetCaption)
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        case let .stale(partial):
            if let partial, partial > 0 {
                Text("\(targets.caloriesKcal) base · +\(partial) kcal syncing from Apple Health")
                    .helmType(.body, color: HelmColor.fgMuted)
            } else {
                Text(ActiveEnergyDisplayCopy.stalePending)
                    .helmType(.body, color: HelmColor.depleted)
            }
        case .unavailable:
            Text(targetCaption)
                .helmType(.body, color: HelmColor.fgMuted)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle)
                    .helmType(.label)
                Spacer()
                Text(snapshot.dayType.rawValue.capitalized)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                if explainMetric != nil, onAskCoach != nil {
                    Button {
                        isShowingTargetExplain = true
                    } label: {
                        HelmIconView(.info, context: .inline)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                    .buttonStyle(.helmPressable)
                    .accessibilityLabel("Show how targets are calculated")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
                if hasCalculatedTargets {
                    HelmNumericText(targets.caloriesKcal)
                        .helmType(.bigNumber)
                    Text("kcal target")
                        .helmType(.body, color: HelmColor.fgMuted)
                } else {
                    Text("Pending")
                        .helmType(.bigNumber, color: HelmColor.fgMuted)
                    Text("kcal target pending")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
                Spacer()
                Text(snapshot.phase.label)
                    .helmType(.monoTag, color: HelmColor.accent)
            }

            if hasCalculatedTargets {
                Text(targetCaption)
                    .helmType(.body, color: HelmColor.fgMuted)
            } else if !hasCalculatedTargets {
                Text("Complete body profile in onboarding or Settings to calculate calorie targets.")
                    .helmType(.body, color: HelmColor.depleted)
            } else if snapshot.targets.caloriesKcal <= 0 {
                Text("Recovered default targets. Tap Refresh if numbers look wrong.")
                    .helmType(.body, color: HelmColor.depleted)
            }
        }
    }

    private var dayTitle: String {
        let today = HelmDay.day(for: Date(), calendar: .current)
        if snapshot.helmDay == today {
            return "Today"
        }
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: DateComponents(
            year: snapshot.helmDay.year,
            month: snapshot.helmDay.month,
            day: snapshot.helmDay.day
        )) else {
            return snapshot.helmDay.formatted
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    private var targetCaption: String {
        switch snapshot.phase {
        case .maintain:
            return "Daily calorie target matches estimated maintenance."
        case .cut:
            return "Daily calorie target is below maintenance for your cut phase."
        case .gain:
            return "Daily calorie target is above maintenance for your gain phase."
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        Divider()
            .overlay(HelmColor.gaugeTrack)

        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Energy estimates")
                .helmType(.label)
            NutritionEnergyEstimatesSection(
                snapshot: snapshot,
                hasCalculatedTargets: hasCalculatedTargets
            )
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

struct NutritionEnergyBalanceSection: View {
    let balance: EnergyBalanceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Energy balance")
                .helmType(.label)

            if let intake = balance.intakeKcal {
                StatRow(
                    label: "Logged in",
                    value: "\(intake) kcal",
                    detail: "Food and drinks logged today"
                )
            } else {
                StatRow(
                    label: "Logged in",
                    value: "None",
                    detail: "No intake logged yet"
                )
            }

            NutritionActiveEnergyStatRow(freshness: balance.activeEnergy)

            StatRow(
                label: "Target",
                value: targetValue,
                detail: targetDetail
            )
        }
    }

    private var targetValue: String {
        if let adjusted = balance.adjustedTargetKcal {
            return "\(adjusted) kcal"
        }
        if balance.baseTargetKcal > 0 {
            return "\(balance.baseTargetKcal) kcal"
        }
        return "Pending"
    }

    private var targetDetail: String {
        if balance.adjustedTargetKcal != nil {
            return "\(balance.baseTargetKcal) base + active energy from Health"
        }
        if case .stale = balance.activeEnergy {
            return "\(balance.baseTargetKcal) base until Apple Health catches up"
        }
        return "Daily calorie target before activity"
    }
}

struct NutritionActiveEnergyStatRow: View {
    let freshness: ActiveEnergyFreshness

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Active out")
                .font(HelmTypography.body)
                .foregroundStyle(HelmColor.textSecondary)

            Spacer(minLength: HelmSpacing.sm)

            VStack(alignment: .trailing, spacing: HelmSpacing.xxs) {
                Text(valueText)
                    .font(HelmTypography.statSmall)
                    .foregroundStyle(valueIsMuted ? HelmColor.textTertiary : HelmColor.textPrimary)
                    .helmNumericRoll(value: valueText)
                Text(detailText)
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var valueText: String {
        switch freshness {
        case .unavailable: "None"
        case .stale(nil): "Pending"
        case let .stale(partial?): "\(partial) kcal"
        case let .fresh(kilocalories): "\(kilocalories) kcal"
        }
    }

    private var detailText: String {
        switch freshness {
        case .unavailable: ActiveEnergyDisplayCopy.unavailableDetail
        case .stale(nil): ActiveEnergyDisplayCopy.stalePending
        case .stale: ActiveEnergyDisplayCopy.stalePartial
        case .fresh: ActiveEnergyDisplayCopy.freshDetail
        }
    }

    private var valueIsMuted: Bool {
        if case .stale = freshness { return true }
        return false
    }
}


struct NutritionEnergyEstimatesSection: View {
    let snapshot: NutritionDaySnapshot
    let hasCalculatedTargets: Bool

    private var targets: MacroTargets { snapshot.targets }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            if let profileMaintenance = snapshot.profileMaintenanceKcal {
                StatRow(
                    label: "Profile maintenance",
                    value: "\(profileMaintenance) kcal",
                    detail: "From body profile (Mifflin-St Jeor)"
                )
            }

            if let tdee = resolvedAdaptiveTDEE {
                StatRow(
                    label: "Current TDEE estimate",
                    value: "\(tdee) kcal",
                    detail: adaptiveTDEEDetail
                )
            } else if hasCalculatedTargets, targets.estimatedTDEEKcal > 0 {
                StatRow(
                    label: "Current TDEE estimate",
                    value: "\(targets.estimatedTDEEKcal) kcal",
                    detail: "Matches profile maintenance until weight and intake refine it"
                )
            } else {
                StatRow(
                    label: "Current TDEE estimate",
                    value: "Pending",
                    detail: "Complete body profile to seed adaptive TDEE"
                )
            }

            if let average = snapshot.trend.weeklyIntakeAverageKcal, average > 0 {
                StatRow(
                    label: "7-day diet average",
                    value: "\(Int(average.rounded())) kcal",
                    detail: "Logged intake over the last week"
                )
            }

            if let weight = snapshot.trend.smoothedTrendWeightKg {
                StatRow(
                    label: "Trend weight",
                    value: String(format: "%.1f kg", weight)
                )
            }

            activeEnergyRow
        }
    }

    @ViewBuilder
    private var activeEnergyRow: some View {
        switch snapshot.activeEnergyFreshness {
        case .unavailable:
            EmptyView()
        case let .stale(partial):
            if let partial, partial > 0 {
                StatRow(
                    label: "Active energy today",
                    value: "\(partial) kcal",
                    detail: ActiveEnergyDisplayCopy.stalePartial
                )
            } else {
                StatRow(
                    label: "Active energy today",
                    value: "Syncing",
                    detail: ActiveEnergyDisplayCopy.stalePending
                )
            }
        case let .fresh(burned):
            StatRow(
                label: "Active energy today",
                value: "\(burned) kcal",
                detail: ActiveEnergyDisplayCopy.freshDetail
            )
        }
    }

    private var resolvedAdaptiveTDEE: Int? {
        if let tdee = snapshot.trend.estimatedTDEEKcal, tdee > 0 {
            return Int(tdee.rounded())
        }
        if hasCalculatedTargets, targets.estimatedTDEEKcal > 0 {
            return targets.estimatedTDEEKcal
        }
        return nil
    }

    private var adaptiveTDEEDetail: String {
        guard let profileMaintenance = snapshot.profileMaintenanceKcal,
              let adaptive = resolvedAdaptiveTDEE else {
            return "Refined from recent food logs and weight trend"
        }
        if abs(adaptive - profileMaintenance) <= 25 {
            return "Aligned with profile maintenance"
        }
        if adaptive < profileMaintenance {
            return "Below profile maintenance based on recent weight and intake"
        }
        return "Above profile maintenance based on recent weight and intake"
    }
}

private extension TrainingPhase {
    var label: String {
        switch self {
        case .cut: "Cut"
        case .maintain: "Maintain"
        case .gain: "Gain"
        }
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
            .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Nutrition summary data sheet") {
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
            .helmScreenPadding()
    }
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}

#Preview("Nutrition summary accessibility") {
    let day = HelmDay(year: 2026, month: 7, day: 23)
    let snapshot = NutritionDaySnapshot(
        helmDay: day,
        targets: MacroTargets(
            caloriesKcal: 2_400,
            proteinGrams: 160,
            carbohydrateGrams: 280,
            fatGrams: 70,
            dayType: .training,
            estimatedTDEEKcal: 2_640,
            macroGapKilocalories: nil
        ),
        actual: nil,
        trend: NutritionTrendState(),
        dayType: .training,
        phase: .maintain
    )

    ScrollView {
        NutritionDaySummaryCard(snapshot: snapshot, showTrend: true)
            .helmScreenPadding()
    }
    .helmTheme()
    .dynamicTypeSize(.accessibility5)
}

#Preview("Active energy fresh") {
    nutritionSummaryPreview(
        activeEnergyKcal: 420,
        activeEnergyFreshness: .fresh(kilocalories: 420)
    )
}

#Preview("Active energy stale pending") {
    nutritionSummaryPreview(
        activeEnergyKcal: nil,
        activeEnergyFreshness: .stale(partialKilocalories: nil)
    )
}

#Preview("Active energy stale partial") {
    nutritionSummaryPreview(
        activeEnergyKcal: 35,
        activeEnergyFreshness: .stale(partialKilocalories: 35)
    )
}

@MainActor
private func nutritionSummaryPreview(
    activeEnergyKcal: Int?,
    activeEnergyFreshness: ActiveEnergyFreshness
) -> some View {
    let day = HelmDay(year: 2026, month: 7, day: 31)
    let actual = NutritionDay(
        helmDay: day,
        totalEnergy: Energy(kilocalories: 1_800),
        totalProteinGrams: 140,
        totalCarbohydrateGrams: 180,
        totalFatGrams: 55,
        macroGapKilocalories: nil
    )
    let targets = MacroTargets(
        caloriesKcal: 2_400,
        proteinGrams: 160,
        carbohydrateGrams: 280,
        fatGrams: 70,
        dayType: .training,
        estimatedTDEEKcal: 2_640,
        macroGapKilocalories: nil
    )
    let snapshot = NutritionDaySnapshot(
        helmDay: day,
        targets: targets,
        actual: actual,
        trend: NutritionTrendState(estimatedTDEEKcal: 2_640, weeklyIntakeAverageKcal: 2_100),
        dayType: .training,
        phase: .maintain,
        activeEnergyKcal: activeEnergyKcal,
        activeEnergyFreshness: activeEnergyFreshness,
        energyBalance: EnergyBalanceSummary.build(
            intakeKcal: 1_800,
            baseTargetKcal: targets.caloriesKcal,
            activeEnergy: activeEnergyFreshness
        )
    )

    return ScrollView {
        NutritionDaySummaryCard(snapshot: snapshot, showTrend: true)
            .helmScreenPadding()
    }
    .helmTheme()
}
