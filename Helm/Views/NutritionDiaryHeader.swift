import Core
import DesignSystem
import SwiftUI

struct NutritionDiaryHeader: View {
    let selectedDay: HelmDay
    let today: HelmDay
    let onSelectDay: (HelmDay) -> Void

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

                HStack(spacing: HelmSpacing.xs) {
                    ForEach(weekDays) { day in
                        dayChip(day)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(weekSwipeGesture)

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

    private func dayChip(_ day: HelmDay) -> some View {
        let isSelected = day == selectedDay
        let isToday = day == today
        return Button {
            HapticEngine.shared.play(.selection)
            onSelectDay(day)
        } label: {
            VStack(spacing: HelmSpacing.xxs) {
                Text(day.shortWeekday)
                    .helmType(.monoTag, color: isSelected ? HelmColor.buttonPrimaryForeground : HelmColor.fgMuted)
                Text("\(day.day)")
                    .helmType(.label, color: isSelected ? HelmColor.buttonPrimaryForeground : HelmColor.fg)
            }
            .frame(width: 44)
            .padding(.vertical, HelmSpacing.xs)
            .background(
                isSelected ? HelmColor.buttonPrimaryBackground : HelmColor.gaugeTrack.opacity(0.25),
                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
            )
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: HelmRadius.sm)
                        .strokeBorder(HelmColor.buttonPrimaryBackground.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.helmPressable)
        .disabled(day > today)
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
