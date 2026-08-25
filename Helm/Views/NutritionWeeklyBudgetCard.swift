import Core
import DesignSystem
import NutritionKit
import SwiftUI

private extension WeeklyNutritionDemand {
    var displayLabel: String {
        switch self {
        case .heavyLift: "Heavy Lift"
        case .lightLift: "Light"
        case .cardio: "Cardio"
        case .rest: "Rest"
        case .restOffice: "Office"
        case .social: "Social"
        case .party: "Party"
        case .highIntake: "High"
        }
    }
}

private extension NutritionDayDemand {
    var budgetPickerLabel: String {
        switch self {
        case .ordinary: "Rest"
        case .office: "Office"
        case .training: "Training"
        case .cardio: "Cardio"
        case .social: "Social"
        case .party: "Party"
        case .highIntake: "High intake"
        }
    }
}

struct NutritionWeeklyBudgetCard: View {
    let budget: WeeklyNutritionBudget
    let today: HelmDay
    var onSetDemand: ((HelmDay, NutritionDayDemand?) -> Void)?

    @State private var editingDay: HelmDay?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("WEEKLY BUDGET")

                summaryRow

                if budget.excessCaloriesKcal > 0 {
                    excessBanner
                }

                dayStrips

                if hasIncompleteElapsedDays {
                    provisionalWarning
                }
            }
        }
        .confirmationDialog(
            demandDialogTitle,
            isPresented: Binding(
                get: { editingDay != nil },
                set: { if !$0 { editingDay = nil } }
            ),
            titleVisibility: .visible
        ) {
            if editingDay != nil {
                ForEach(NutritionDayDemand.allCases, id: \.self) { demand in
                    Button(demand.budgetPickerLabel) {
                        guard let day = editingDay else { return }
                        onSetDemand?(day, demand)
                        editingDay = nil
                    }
                }
                Button("Use plan") {
                    guard let day = editingDay else { return }
                    onSetDemand?(day, nil)
                    editingDay = nil
                }
                Button("Cancel", role: .cancel) {
                    editingDay = nil
                }
            }
        }
    }

    private var demandDialogTitle: String {
        guard let editingDay else { return "Day type" }
        if editingDay == today { return "Today" }
        return editingDay.shortWeekday
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack(spacing: HelmSpacing.md) {
            summaryStat(
                label: "Target",
                value: budget.targetCaloriesKcal,
                color: HelmColor.fg
            )
            summaryStat(
                label: "Consumed",
                value: budget.consumedCaloriesKcal,
                color: HelmColor.ready
            )
            summaryStat(
                label: "Remaining",
                value: budget.remainingCaloriesKcal,
                color: budget.remainingCaloriesKcal > 0
                    ? HelmColor.fg
                    : HelmColor.depleted
            )
        }
    }

    private func summaryStat(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
                HelmNumericText(value)
                    .helmType(.number, color: color)
                Text("kcal")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Excess

    private var excessBanner: some View {
        HStack(spacing: HelmSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(HelmColor.compromised)
            Text("\(budget.excessCaloriesKcal) kcal over weekly target")
                .helmType(.body, color: HelmColor.compromised)
        }
        .padding(.horizontal, HelmSpacing.sm)
        .padding(.vertical, HelmSpacing.xs)
        .background(
            HelmColor.compromised.opacity(0.12),
            in: RoundedRectangle(cornerRadius: HelmRadius.sm)
        )
    }

    // MARK: - Day strips

    private var dayStrips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HelmSpacing.xs) {
                ForEach(budget.days) { day in
                    dayStrip(day)
                        .onTapGesture {
                            editingDay = day.day
                        }
                }
            }
        }
    }

    private func dayStrip(_ day: WeeklyNutritionBudgetDay) -> some View {
        let isToday = day.day == today

        return VStack(alignment: .center, spacing: HelmSpacing.xxs) {
            Text(dayStripDayLabel(day.day))
                .helmType(.monoTag, color: isToday
                    ? HelmColor.accent
                    : HelmColor.fgMuted)

            HelmNumericText(day.caloriesKcal)
                .helmType(.number, color: dayCalorieColor(day))

            Text("kcal")
                .helmType(.monoTag, color: HelmColor.fgMuted)

            Text(day.demand.displayLabel)
                .helmType(.monoTag, color: demandTagColor(day.demand))
                .lineLimit(1)

            if day.state == .provisional, day.day < today {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(HelmColor.compromised)
            }
        }
        .frame(minWidth: 68)
        .padding(.horizontal, HelmSpacing.xs)
        .padding(.vertical, HelmSpacing.sm)
        .background(stripBackground(isToday: isToday, state: day.state))
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: HelmRadius.sm)
                    .strokeBorder(HelmColor.accent.opacity(0.5), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(dayStripDayLabel(day.day)), \(day.caloriesKcal) kcal, \(day.demand.displayLabel)"
        )
        .accessibilityHint("Changes the day type")
    }

    private func dayStripDayLabel(_ helmDay: HelmDay) -> String {
        if helmDay == today { return "TODAY" }
        return helmDay.shortWeekday.uppercased()
    }

    private func dayCalorieColor(_ day: WeeklyNutritionBudgetDay) -> Color {
        switch day.state {
        case .consumed: HelmColor.ready
        case .remaining: HelmColor.accent
        case .provisional: HelmColor.fgSecondary
        }
    }

    private func stripBackground(isToday: Bool, state: WeeklyNutritionBudgetDayState) -> Color {
        if isToday { return HelmColor.accent.opacity(0.10) }
        switch state {
        case .consumed: return HelmColor.ready.opacity(0.08)
        case .remaining: return HelmColor.surface
        case .provisional: return HelmColor.surface.opacity(0.55)
        }
    }

    private func demandTagColor(_ demand: WeeklyNutritionDemand) -> Color {
        switch demand {
        case .heavyLift: HelmColor.primed
        case .lightLift: HelmColor.ready
        case .cardio: HelmColor.accent
        case .rest: HelmColor.fgMuted
        case .restOffice: HelmColor.fgSecondary
        case .social: HelmColor.compromised
        case .party: HelmColor.compromised
        case .highIntake: HelmColor.fgSecondary
        }
    }

    // MARK: - Warnings

    private var hasIncompleteElapsedDays: Bool {
        budget.days.contains { day in
            day.state != .consumed && day.day < today
        }
    }

    private var provisionalWarning: some View {
        HStack(spacing: HelmSpacing.xs) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(HelmColor.fgMuted)
            Text("Past days with no food log keep their planned target. Remaining days are not padded.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
        .padding(.horizontal, HelmSpacing.sm)
        .padding(.vertical, HelmSpacing.xs)
        .background(
            HelmColor.fgMuted.opacity(0.08),
            in: RoundedRectangle(cornerRadius: HelmRadius.sm)
        )
    }
}

// MARK: - Previews

#if DEBUG

private func previewBudget(consumedDays: Int = 2) -> WeeklyNutritionBudget {
    let monday = HelmDay(year: 2026, month: 8, day: 24)
    let demands: [WeeklyNutritionDemand] = [
        .heavyLift, .lightLift, .restOffice, .heavyLift, .cardio, .social, .party,
    ]
    var consumed: [Int: Int] = [:]
    for i in 0 ..< consumedDays {
        consumed[i] = [2_200, 2_100, 1_800, 2_400, 2_300, 3_100, 2_500][i]
    }
    let inputs: [WeeklyNutritionBudgetDayInput] = demands.indices.map { i in
        WeeklyNutritionBudgetDayInput(
            day: monday.adding(days: i),
            demand: demands[i],
            consumedCaloriesKcal: consumed[i]
        )
    }
    return WeeklyNutritionBudgetCalculator.calculate(
        weekStart: monday,
        weeklyCaloriesKcal: 17_500,
        proteinGramsPerDay: 160,
        days: inputs,
        asOf: monday.adding(days: consumedDays)
    )
}

#Preview("Weekly budget midweek") {
    ScrollView {
        NutritionWeeklyBudgetCard(
            budget: previewBudget(consumedDays: 2),
            today: HelmDay(year: 2026, month: 8, day: 26)
        )
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Weekly budget excess") {
    let budget = WeeklyNutritionBudgetCalculator.calculate(
        weekStart: HelmDay(year: 2026, month: 8, day: 24),
        weeklyCaloriesKcal: 14_000,
        proteinGramsPerDay: 150,
        days: (0 ..< 7).map { i in
            WeeklyNutritionBudgetDayInput(
                day: HelmDay(year: 2026, month: 8, day: 24).adding(days: i),
                demand: [.heavyLift, .party, .social, .heavyLift, .cardio, .party, .highIntake][i],
                consumedCaloriesKcal: i <= 5 ? [3_000, 2_800, 2_600, 3_200, 2_500, 3_500][i] : nil
            )
        },
        asOf: HelmDay(year: 2026, month: 8, day: 30)
    )
    ScrollView {
        NutritionWeeklyBudgetCard(
            budget: budget,
            today: HelmDay(year: 2026, month: 8, day: 30)
        )
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Weekly budget data sheet") {
    ScrollView {
        NutritionWeeklyBudgetCard(
            budget: previewBudget(consumedDays: 4),
            today: HelmDay(year: 2026, month: 8, day: 28)
        )
        .helmScreenPadding()
    }
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}

#Preview("Weekly budget accessibility") {
    ScrollView {
        NutritionWeeklyBudgetCard(
            budget: previewBudget(consumedDays: 1),
            today: HelmDay(year: 2026, month: 8, day: 25)
        )
        .helmScreenPadding()
    }
    .helmTheme()
    .dynamicTypeSize(.accessibility5)
}

#endif