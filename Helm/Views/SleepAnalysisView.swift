import Core
import DesignSystem
import SwiftUI

struct SleepAnalysisView: View {
    let model: SleepAnalysisModel

    var body: some View {
        ScrollView {
            HelmScreenStack {
                tonightCard
                    .helmStaggeredAppear(index: 0)

                stagesCard
                    .helmStaggeredAppear(index: 1)

                recentCard
                    .helmStaggeredAppear(index: 2)
            }
            .helmScreenPadding()
        }
        .helmScreenBackground()
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tonightCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("LAST NIGHT")

                if let asleepHours = model.tonight.asleepHours {
                    Text(SleepDurationFormatting.hoursAndMinutes(from: asleepHours))
                        .helmType(.heroNumber)
                        .accessibilityLabel(
                            "Time asleep \(SleepDurationFormatting.hoursAndMinutes(from: asleepHours))"
                        )

                    if let efficiency = model.tonight.efficiency {
                        Text("\(Int((efficiency * 100).rounded()))% efficiency")
                            .helmType(.body, color: HelmColor.fgSecondary)
                    }
                } else {
                    Text("No sleep data for last night")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
    }

    private var stagesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("STAGES")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: HelmSpacing.sm),
                        GridItem(.flexible(), spacing: HelmSpacing.sm)
                    ],
                    spacing: HelmSpacing.sm
                ) {
                    StatChip(
                        label: "Deep",
                        value: minutesLabel(model.tonight.deepMinutes)
                    )
                    StatChip(
                        label: "REM",
                        value: minutesLabel(model.tonight.remMinutes)
                    )
                    StatChip(
                        label: "Awake",
                        value: minutesLabel(model.tonight.awakeMinutes)
                    )
                    StatChip(
                        label: "In bed",
                        value: hoursLabel(model.tonight.inBedHours)
                    )
                }
            }
        }
    }

    private var recentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("RECENT NIGHTS")

                if model.recentNights.isEmpty {
                    Text("Sleep nights will appear here after HealthKit sync.")
                        .helmType(.body, color: HelmColor.fgMuted)
                } else {
                    VStack(spacing: HelmSpacing.sm) {
                        ForEach(model.recentNights) { night in
                            HStack {
                                Text(dayLabel(night.wakeDay))
                                    .helmType(.label)
                                Spacer()
                                if let asleep = night.summary.asleepHours {
                                    Text(SleepDurationFormatting.hoursAndMinutes(from: asleep))
                                        .helmType(.number)
                                        .monospacedDigit()
                                }
                                if let efficiency = night.summary.efficiency {
                                    Text("\(Int((efficiency * 100).rounded()))%")
                                        .helmType(.monoTag, color: HelmColor.fgMuted)
                                        .frame(width: HelmSpacing.xl + HelmSpacing.sm, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func minutesLabel(_ minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return "-" }
        return SleepDurationFormatting.hoursAndMinutes(from: minutes / 60.0)
    }

    private func hoursLabel(_ hours: Double?) -> String {
        guard let hours, hours > 0 else { return "-" }
        return SleepDurationFormatting.hoursAndMinutes(from: hours)
    }

    private func dayLabel(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle()
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .locale(Locale(identifier: "en_US_POSIX"))
        )
        .replacingOccurrences(of: ", ", with: " · ")
    }
}

#Preview("Sleep analysis") {
    NavigationStack {
        SleepAnalysisView(
            model: SleepAnalysisModel(
                tonight: SleepNightSummary(
                    asleepHours: 7.25,
                    inBedHours: 8.0,
                    awakeMinutes: 28,
                    deepMinutes: 95,
                    remMinutes: 110,
                    efficiency: 0.91
                ),
                recentNights: [
                    SleepAnalysisNight(
                        wakeDay: Date(),
                        summary: SleepNightSummary(asleepHours: 7.25, efficiency: 0.91)
                    ),
                    SleepAnalysisNight(
                        wakeDay: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
                        summary: SleepNightSummary(asleepHours: 6.4, efficiency: 0.84)
                    )
                ]
            )
        )
    }
    .helmTheme()
}
