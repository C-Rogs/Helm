import Core
import DesignSystem
import HealthKitIngest
import NutritionKit
import SwiftUI

struct NutritionWeeklyCheckInSheet: View {
    let asOf: HelmDay
    let onConfirmed: () -> Void

    @State private var preview: NutritionWeeklyCheckInPreview?
    @State private var includedOverrides: [HelmDay: Bool] = [:]
    @State private var isLoading = true
    @State private var isApplying = false
    @State private var didConfirm = false
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    private let preferences = NutritionPreferencesStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if didConfirm {
                    confirmationContent
                } else if isLoading {
                    ProgressView("Loading week…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    ContentUnavailableView(
                        "Check-in unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else if let preview {
                    checkInForm(preview)
                }
            }
            .navigationTitle("Weekly check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isApplying)
                }
            }
            .helmScreenBackground()
            .task { await reload() }
        }
    }

    private var confirmationContent: some View {
        VStack(spacing: HelmSpacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(HelmColor.primed)
            Text("Targets updated")
                .helmType(.title)
            Text("Your calorie and macro targets reflect this week's reconcile.")
                .helmType(.body, color: HelmColor.fgSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, HelmSpacing.lg)
            Spacer()
            Button("Done") {
                onConfirmed()
                dismiss()
            }
            .buttonStyle(.helmPrimary)
            .padding(.horizontal, HelmSpacing.lg)
            .padding(.bottom, HelmSpacing.lg)
        }
    }

    @ViewBuilder
    private func checkInForm(_ preview: NutritionWeeklyCheckInPreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Card {
                    VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                        HelmSectionEyebrow("LAST 7 DAYS")
                        Text("\(preview.windowStart.formattedLabel) to \(preview.asOf.formattedLabel)")
                            .helmType(.body, color: HelmColor.fgSecondary)
                        confidenceRow(preview)
                        Text("\(preview.weighInDays) weigh-ins · \(preview.foodDays) food days included")
                            .helmType(.body, color: HelmColor.fgMuted)
                        if !preview.meetsSoftGate {
                            Text("Need at least 3 weigh-ins and 3 food days for a confident update.")
                                .helmType(.body, color: HelmColor.compromised)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                        HelmSectionEyebrow("DAYS")
                        ForEach(preview.days) { day in
                            dayRow(day)
                            if day.id != preview.days.last?.id {
                                HelmHairlineRule()
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                        HelmSectionEyebrow("PROPOSED TARGETS")
                        targetDeltaRow(
                            label: "Calories",
                            current: preview.currentCaloriesKcal,
                            proposed: preview.proposedCaloriesKcal,
                            unit: "kcal"
                        )
                        targetDeltaRow(
                            label: "Protein",
                            current: preview.currentProteinGrams,
                            proposed: preview.proposedProteinGrams,
                            unit: "g"
                        )
                        targetDeltaRow(
                            label: "TDEE",
                            current: preview.currentTDEEKcal,
                            proposed: preview.proposedTDEEKcal,
                            unit: "kcal"
                        )
                    }
                }

                Button {
                    Task { await confirm(preview) }
                } label: {
                    Text(isApplying ? "Updating…" : "Confirm update")
                }
                .buttonStyle(.helmPrimary)
                .disabled(isApplying || !preview.meetsSoftGate)

                if !preview.meetsSoftGate {
                    Text("Add weigh-ins or complete more food days, then reopen check-in.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
            .helmScreenPadding()
            .padding(.bottom, HelmSpacing.lg)
        }
    }

    private func confidenceRow(_ preview: NutritionWeeklyCheckInPreview) -> some View {
        HStack(spacing: HelmSpacing.xs) {
            Text("Confidence")
                .helmType(.label)
            Spacer()
            Text(preview.confidence.displayName.uppercased())
                .helmType(.monoTag, color: confidenceColor(preview.confidence))
        }
    }

    private func confidenceColor(_ confidence: NutritionWeeklyCheckInConfidence) -> Color {
        switch confidence {
        case .high: HelmColor.primed
        case .moderate: HelmColor.ready
        case .needsData: HelmColor.compromised
        }
    }

    private func dayRow(_ day: NutritionWeeklyCheckInDayRow) -> some View {
        Toggle(isOn: Binding(
            get: { day.isIncluded },
            set: { newValue in
                includedOverrides[day.helmDay] = newValue
                Task { await reload() }
            }
        )) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(day.helmDay.formattedLabel)
                    .helmType(.label)
                HStack(spacing: HelmSpacing.sm) {
                    statusChip(day.hasWeighIn ? "Weigh-in" : "No weigh-in", ok: day.hasWeighIn)
                    statusChip(day.hasFoodLog ? "Food" : "No food", ok: day.hasFoodLog)
                    if day.isIncomplete {
                        statusChip("Incomplete", ok: false)
                    } else if day.loggingComplete {
                        statusChip("Complete", ok: true)
                    }
                }
                if let logged = day.loggedKcal {
                    let goal = day.goalKcal.map { " / \($0)" } ?? ""
                    Text("\(logged)\(goal) kcal")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
        .tint(HelmColor.accent)
    }

    private func statusChip(_ text: String, ok: Bool) -> some View {
        Text(text)
            .helmType(.monoTag, color: ok ? HelmColor.ready : HelmColor.fgMuted)
    }

    private func targetDeltaRow(label: String, current: Int, proposed: Int, unit: String) -> some View {
        let delta = proposed - current
        let deltaText: String = {
            if delta == 0 { return "unchanged" }
            let sign = delta > 0 ? "+" : ""
            return "\(sign)\(delta) \(unit)"
        }()
        return HStack {
            Text(label)
                .helmType(.label)
            Spacer()
            VStack(alignment: .trailing, spacing: HelmSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xxs) {
                    HelmNumericText(current)
                        .helmType(.number, color: HelmColor.fgMuted)
                    Text("→")
                        .helmType(.body, color: HelmColor.fgMuted)
                    HelmNumericText(proposed)
                        .helmType(.number, color: HelmColor.fg)
                    Text(unit)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
                Text(deltaText)
                    .helmType(.monoTag, color: delta == 0 ? HelmColor.fgMuted : (delta > 0 ? HelmColor.ready : HelmColor.depleted))
            }
        }
    }

    @MainActor
    private func reload() async {
        isLoading = preview == nil
        loadError = nil
        do {
            let built = try await NutritionBootstrap.weeklyCheckInService.buildPreview(
                asOf: asOf,
                includedOverrides: includedOverrides.isEmpty ? nil : includedOverrides
            )
            preview = built
            if includedOverrides.isEmpty {
                includedOverrides = Dictionary(uniqueKeysWithValues: built.days.map { ($0.helmDay, $0.isIncluded) })
            }
        } catch {
            loadError = "Could not load the last 7 days."
        }
        isLoading = false
    }

    @MainActor
    private func confirm(_ preview: NutritionWeeklyCheckInPreview) async {
        isApplying = true
        defer { isApplying = false }
        do {
            _ = try await NutritionBootstrap.weeklyCheckInService.apply(
                asOf: preview.asOf,
                includedOverrides: includedOverrides
            )
            preferences.setLastCheckInCompletedOn(preview.asOf)
            HapticEngine.shared.play(.mealConfirmed)
            didConfirm = true
            onConfirmed()
        } catch {
            loadError = "Could not apply the weekly update."
        }
    }
}

#Preview("Weekly check-in") {
    NutritionWeeklyCheckInSheet(
        asOf: HelmDay(year: 2026, month: 9, day: 7),
        onConfirmed: {}
    )
    .helmTheme()
}
