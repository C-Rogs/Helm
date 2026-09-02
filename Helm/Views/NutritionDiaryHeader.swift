import Core
import DesignSystem
import NutritionKit
import SwiftUI

struct NutritionDiaryHeader: View {
    let selectedDay: HelmDay
    let today: HelmDay
    var budget: WeeklyNutritionBudget?
    var onSelectDay: (HelmDay) -> Void
    var onSetDemand: ((HelmDay, NutritionDayDemand?) -> Void)?

    private var weekDays: [HelmDay] {
        let calendar = Calendar(identifier: .gregorian)
        guard let anchor = calendar.date(from: DateComponents(year: selectedDay.year, month: selectedDay.month, day: selectedDay.day)) else {
            return [selectedDay]
        }
        let weekday = calendar.component(.weekday, from: anchor)
        let startOffset = weekday - calendar.firstWeekday
        let normalizedOffset = startOffset < 0 ? startOffset + 7 : startOffset
        guard let weekStart = calendar.date(byAdding: .day, value: -normalizedOffset, to: anchor) else {
            return [selectedDay]
        }
        return (0 ..< 7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return HelmDay.calendarDay(for: date, calendar: calendar)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack(spacing: HelmSpacing.xs) {
                Button {
                    onSelectDay(selectedDay.adding(days: -1))
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.helmPressable)
                .accessibilityLabel("Previous day")

                HStack(spacing: HelmSpacing.xxs) {
                    ForEach(weekDays) { day in
                        dayChip(day)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .highPriorityGesture(weekSwipeGesture)

                Button {
                    goToNextDay()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.helmPressable)
                .disabled(selectedDay >= today)
                .accessibilityLabel("Next day")
            }

            if selectedDay != today {
                Button("Jump to today") {
                    onSelectDay(today)
                }
                .buttonStyle(.helmSecondary)
            }
        }
    }

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                if value.translation.width < -32 {
                    goToNextWeek()
                } else if value.translation.width > 32 {
                    goToPreviousWeek()
                }
            }
    }

    private func goToPreviousWeek() {
        onSelectDay(selectedDay.adding(days: -7))
    }

    private func goToNextWeek() {
        let candidate = selectedDay.adding(days: 7)
        onSelectDay(candidate <= today ? candidate : today)
    }

    private func goToNextDay() {
        guard selectedDay < today else { return }
        onSelectDay(selectedDay.adding(days: 1))
    }

    private func budgetDay(for day: HelmDay) -> WeeklyNutritionBudgetDay? {
        budget?.day(for: day)
    }

    private func dayChip(_ day: HelmDay) -> some View {
        let isSelected = day == selectedDay
        let isToday = day == today
        let budgetDay = budgetDay(for: day)
        let foreground = isSelected ? HelmColor.buttonPrimaryForeground : HelmColor.fg
        let muted = isSelected ? HelmColor.buttonPrimaryForeground.opacity(0.7) : HelmColor.fgMuted

        return Button {
            HapticEngine.shared.play(.selection)
            onSelectDay(day)
        } label: {
            VStack(spacing: HelmSpacing.xxs) {
                Text(day.shortWeekday)
                    .helmType(.monoTag, color: muted)
                Text("\(day.day)")
                    .helmType(.label, color: foreground)
                if let eatTo = budgetDay?.eatToCaloriesKcal, eatTo > 0 {
                    HelmNumericText(eatTo)
                        .helmType(.monoTag, color: isSelected ? muted : chipKcalColor(budgetDay))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.xs)
            .background(chipBackground(isSelected: isSelected, state: budgetDay?.state), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: HelmRadius.sm)
                        .strokeBorder(HelmColor.accent.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.helmPressable)
        .disabled(day > today)
        .contextMenu {
            if let onSetDemand, day <= today {
                ForEach(NutritionDayDemand.allCases, id: \.self) { demand in
                    Button(demand.budgetPickerLabel) {
                        onSetDemand(day, demand)
                    }
                }
                Button("Use plan") {
                    onSetDemand(day, nil)
                }
            }
        }
        .accessibilityLabel(chipAccessibilityLabel(day: day, budgetDay: budgetDay, isToday: isToday))
        .accessibilityHint(onSetDemand == nil ? "Selects the day" : "Selects the day. Touch and hold to change day type.")
    }

    private func chipBackground(
        isSelected: Bool,
        state: WeeklyNutritionBudgetDayState?
    ) -> Color {
        if isSelected { return HelmColor.buttonPrimaryBackground }
        switch state {
        case .consumed: return HelmColor.ready.opacity(0.12)
        case .remaining: return HelmColor.accent.opacity(0.10)
        case .provisional: return HelmColor.gaugeTrack.opacity(0.18)
        case nil: return HelmColor.gaugeTrack.opacity(0.25)
        }
    }

    private func chipKcalColor(_ budgetDay: WeeklyNutritionBudgetDay?) -> Color {
        guard let budgetDay else { return HelmColor.fgMuted }
        switch budgetDay.state {
        case .consumed: return HelmColor.ready
        case .remaining: return HelmColor.accent
        case .provisional: return HelmColor.fgSecondary
        }
    }

    private func chipAccessibilityLabel(
        day: HelmDay,
        budgetDay: WeeklyNutritionBudgetDay?,
        isToday: Bool
    ) -> String {
        var parts = [isToday ? "Today" : day.shortWeekday]
        if let budgetDay {
            parts.append("\(budgetDay.eatToCaloriesKcal) kcal")
            parts.append(budgetDay.demand.displayLabel)
        }
        return parts.joined(separator: ", ")
    }
}

extension NutritionDayDemand {
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

#Preview {
    NutritionDiaryHeader(
        selectedDay: HelmDay(year: 2026, month: 7, day: 24),
        today: HelmDay(year: 2026, month: 7, day: 24),
        onSelectDay: { _ in }
    )
    .padding()
    .helmTheme()
}
