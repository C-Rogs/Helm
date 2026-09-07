import Core
import DesignSystem
import HealthKitIngest
import Persistence
import PlanKit
import SwiftUI

/// Idle Train strip: phase / split / days / duration / equipment, or warm empty CTA.
struct TrainPlanStrip: View {
    var phaseNarrative: String?

    @State private var content: Content = .loading
    @State private var isShowingPlanBuilder = false

    private enum Content: Equatable {
        case loading
        case empty
        case plan(title: String, detail: String)
    }

    var body: some View {
        Button {
            isShowingPlanBuilder = true
        } label: {
            Card {
                HStack(alignment: .top, spacing: HelmSpacing.sm) {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        HelmSectionEyebrow("YOUR PLAN", showsArcMark: false)
                        switch content {
                        case .loading:
                            Text("Loading plan…")
                                .helmType(.title, color: HelmColor.fgMuted)
                        case .empty:
                            Text("Build your plan")
                                .helmType(.title)
                            Text("Set phase, days, split, and equipment.")
                                .helmType(.body, color: HelmColor.fgSecondary)
                        case let .plan(title, detail):
                            Text(title)
                                .helmType(.title)
                                .lineLimit(2)
                            Text(detail)
                                .helmType(.body, color: HelmColor.fgSecondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: HelmSpacing.sm)
                    HelmIconView(.chevronRight, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                        .padding(.top, HelmSpacing.xxs)
                }
            }
        }
        .buttonStyle(.helmPressableCard)
        .accessibilityLabel(accessibilityLabel)
        .sheet(isPresented: $isShowingPlanBuilder, onDismiss: {
            Task { await reload() }
        }) {
            PlanBuilderFlowView(hidesMaintenanceField: false)
        }
        .task {
            await reload()
        }
        .onChange(of: phaseNarrative) { _, _ in
            Task { await reload() }
        }
    }

    private var accessibilityLabel: String {
        switch content {
        case .loading:
            return "Your plan, loading"
        case .empty:
            return "Your plan. Build your plan"
        case let .plan(title, detail):
            return "Your plan. \(title). \(detail)"
        }
    }

    @MainActor
    private func reload() async {
        let store = PersistenceBootstrap.persistenceStore
        do {
            let hasPlan = try store.trainingPlan.hasStoredSettings()
            guard hasPlan else {
                content = .empty
                return
            }
            let settings = try store.trainingPlan.load()
            let equipment = MethodologyPreferences.parse(
                from: (try? store.memoryProfile.load().preferences) ?? ""
            ).preferences.allowedEquipment
            let snapshot = TrainPlanStripModel.make(
                settings: settings,
                phaseNarrative: phaseNarrative,
                allowedEquipment: equipment
            )
            content = .plan(title: snapshot.title, detail: snapshot.detail)
        } catch {
            content = .empty
        }
    }
}

enum TrainPlanStripModel {
    struct Snapshot: Equatable {
        var title: String
        var detail: String
    }

    static func make(
        settings: StoredTrainingPlanSettings,
        phaseNarrative: String?,
        allowedEquipment: Set<String>
    ) -> Snapshot {
        let title: String = {
            let narrative = phaseNarrative?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !narrative.isEmpty {
                return narrative
            }
            let phase = settings.phaseGoal.phase.rawValue.capitalized
            return "\(phase) · \(settings.daysPerWeek) days/wk"
        }()

        var parts: [String] = []
        parts.append(splitLabel(for: settings))
        parts.append("\(settings.daysPerWeek) days")
        parts.append(SessionDurationBudget.from(minutes: settings.sessionDurationMinutes).label)
        if let equipment = equipmentSummary(allowedEquipment) {
            parts.append(equipment)
        }
        if let focus = settings.phaseGoal.musclePrioritiesDisplayLabel {
            parts.append("Focus \(focus)")
        }

        return Snapshot(title: title, detail: parts.joined(separator: " · "))
    }

    static func splitLabel(for settings: StoredTrainingPlanSettings) -> String {
        if let template = ProgramTemplate(rawValue: settings.programTemplateRaw) {
            return template.label
        }
        let rotation = TrainingPlanShape.dayKindRotation(from: settings)
        let labels = rotation.map(\.label)
        let unique = labels.reduce(into: [String]()) { acc, label in
            if !acc.contains(label) { acc.append(label) }
        }
        return unique.isEmpty ? "Custom" : unique.joined(separator: " / ")
    }

    static func equipmentSummary(_ allowed: Set<String>) -> String? {
        let sorted = allowed
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
        guard !sorted.isEmpty else { return nil }
        if sorted.count <= 3 {
            return sorted.map(\.localizedCapitalized).joined(separator: ", ")
        }
        return "\(sorted.count) equipment"
    }
}
