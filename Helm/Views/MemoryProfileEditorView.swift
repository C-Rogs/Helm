import CoachLLM
import Core
import DesignSystem
import Persistence
import SwiftUI

struct MemoryProfileEditorView: View {
    @State private var profile = MemoryProfile.empty
    @State private var saveMessage: String?
    @State private var isSaving = false
    @ScaledMetric(relativeTo: .body) private var editorMinHeight: CGFloat = 80

    var body: some View {
        Form {
            Section {
                Text("Coach reads this memory every turn. Edit freely; changes apply on the next chat.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Baselines") {
                editorField("Summary", text: $profile.baselinesSummary)
            }
            .listRowBackground(HelmColor.surface)

            Section("Mesocycle") {
                editorField("Position", text: $profile.mesocyclePosition)
            }
            .listRowBackground(HelmColor.surface)

            Section("Phase") {
                Text("Edit phase, rate, and emphasis under Settings - Training Plan.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
                if let phaseGoal = profile.phaseGoal {
                    LabeledContent("Current phase", value: phaseGoal.phase.label)
                    if let emphasis = phaseGoal.emphasis, !emphasis.isEmpty {
                        LabeledContent("Emphasis", value: emphasis)
                    }
                }
            }
            .listRowBackground(HelmColor.surface)

            Section("Preferences") {
                editorField("Notes", text: $profile.preferences)
            }
            .listRowBackground(HelmColor.surface)

            Section("Standing Constraints") {
                editorField("Constraints", text: $profile.standingConstraints)
                Text("Temporary recovery notes use dated until/joint tags for any joint (shoulder, knee, hip, ...). Coach can save via chat confirm. Example: 2026-08-05 [until:2026-08-08] [joint:knee] Soft pause deep knee bends.")
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgSecondary)
            }
            .listRowBackground(HelmColor.surface)

            Section("What Has Worked") {
                editorField("Notes", text: $profile.whatHasWorked)
            }
            .listRowBackground(HelmColor.surface)

            Section("Active Modules") {
                if profile.activeModules.isEmpty {
                    Text("No active modules.")
                        .font(HelmType.body.font)
                        .foregroundStyle(HelmColor.fgMuted)
                } else {
                    ForEach(profile.activeModules, id: \.self) { module in
                        Text(module)
                            .font(HelmType.body.font)
                    }
                }
            }
            .listRowBackground(HelmColor.surface)

            Section("Injury History") {
                editorField("History", text: $profile.injuryHistory)
            }
            .listRowBackground(HelmColor.surface)

            Section("Training Responses") {
                editorField("Responses", text: $profile.trainingResponses)
            }
            .listRowBackground(HelmColor.surface)

            Section("Nutrition Patterns") {
                editorField("Patterns", text: $profile.nutritionPatterns)
            }
            .listRowBackground(HelmColor.surface)

            Section("Pending Refinements") {
                let count = profile.pendingRefinements.count
                Text("\(count) refinement\(count == 1 ? "" : "s") pending confirmation.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
                Text("View in Chat to accept or dismiss.")
                    .font(HelmType.monoTag.font)
                    .foregroundStyle(HelmColor.fgMuted)
            }
            .listRowBackground(HelmColor.surface)

            Section("Coach Style - Global") {
                stylePickers(for: $profile.globalStyle)
            }
            .listRowBackground(HelmColor.surface)

            Section("Coach Style - Training") {
                stylePickers(for: $profile.trainingStyle)
            }
            .listRowBackground(HelmColor.surface)

            Section("Coach Style - Nutrition") {
                stylePickers(for: $profile.nutritionStyle)
            }
            .listRowBackground(HelmColor.surface)

            Section("Coach Style - Recovery") {
                stylePickers(for: $profile.recoveryStyle)
            }
            .listRowBackground(HelmColor.surface)

            if let saveMessage {
                Section {
                    Text(saveMessage)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
            }

            Section {
                Button(isSaving ? "Saving..." : "Save Memory") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Coach Memory")
        .helmScreenBackground()
        .task { await load() }
    }

    @ViewBuilder
    private func editorField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text(title)
                .font(HelmType.monoTag.font)
                .foregroundStyle(HelmColor.fgMuted)
            TextEditor(text: text)
                .frame(minHeight: editorMinHeight)
                .scrollContentBackground(.hidden)
                .padding(HelmSpacing.xs)
                .background(HelmColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
    }

    @ViewBuilder
    private func stylePickers(for binding: Binding<CoachStyleProfile?>) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            styleSegment(
                label: "Detail",
                selection: binding.wrappedValue?.detail ?? .balanced,
                cases: CoachStyleProfile.Detail.allCases
            ) { new in
                var copy = binding.wrappedValue ?? CoachStyleProfile()
                copy.detail = new
                copy.source = .explicit
                binding.wrappedValue = copy
            }
            styleSegment(
                label: "Depth",
                selection: binding.wrappedValue?.depth ?? .mixed,
                cases: CoachStyleProfile.Depth.allCases
            ) { new in
                var copy = binding.wrappedValue ?? CoachStyleProfile()
                copy.depth = new
                copy.source = .explicit
                binding.wrappedValue = copy
            }
            styleSegment(
                label: "Encouragement",
                selection: binding.wrappedValue?.encouragement ?? .balanced,
                cases: CoachStyleProfile.Encouragement.allCases
            ) { new in
                var copy = binding.wrappedValue ?? CoachStyleProfile()
                copy.encouragement = new
                copy.source = .explicit
                binding.wrappedValue = copy
            }
            styleSegment(
                label: "Directive",
                selection: binding.wrappedValue?.directive ?? .balanced,
                cases: CoachStyleProfile.Directive.allCases
            ) { new in
                var copy = binding.wrappedValue ?? CoachStyleProfile()
                copy.directive = new
                copy.source = .explicit
                binding.wrappedValue = copy
            }
        }
    }

    private func styleSegment<T: Hashable & CaseIterable>(
        label: String,
        selection: T,
        cases: T.AllCases,
        onChange: @escaping (T) -> Void
    ) -> some View where T.AllCases: RandomAccessCollection, T: RawRepresentable, T.RawValue == String {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .font(HelmType.monoTag.font)
                .foregroundStyle(HelmColor.fgMuted)
            Picker(label, selection: Binding<T>(get: { selection }, set: onChange)) {
                ForEach(Array(cases), id: \.self) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @MainActor
    private func load() async {
        do {
            let loaded = try PersistenceBootstrap.persistenceStore.memoryProfile.load()
            profile = loaded
        } catch {
            saveMessage = "Could not load memory: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await HelmActionRuntime.perform(
                .memory(.replaceProfile(profile)),
                after: .coach
            )
            saveMessage = "Saved. Coach will use this on the next turn."
        } catch {
            saveMessage = error.localizedDescription
        }
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
    NavigationStack {
        MemoryProfileEditorView()
    }
    .helmTheme()
}
