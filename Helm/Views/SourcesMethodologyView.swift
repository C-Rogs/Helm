import CoachLLM
import Core
import DesignSystem
import HealthKitIngest
import NutritionKit
import Persistence
import SwiftUI

struct SourcesMethodologyView: View {
    @State private var document = MethodologyBootstrap.document
    @State private var preferences = MethodologyPreferences.default
    @State private var loadedPreferences = MethodologyPreferences.default
    @State private var prescriptionCitations: [EvidenceRecord] = []
    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var selectedTopic: MethodologyTopic?

    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }

    var body: some View {
        List {
            if !prescriptionCitations.isEmpty {
                Section("Today's programme") {
                    ForEach(prescriptionCitations) { record in
                        CitationRow(record: record)
                    }
                }
            }

            Section("Food reference data") {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text(CoFIDAttribution.title)
                        .font(HelmType.label.font)
                        .foregroundStyle(HelmColor.fg)
                    Text(CoFIDAttribution.sourceName)
                        .font(HelmType.body.font)
                        .foregroundStyle(HelmColor.fgSecondary)
                    Text(CoFIDAttribution.licenceNotice)
                        .font(HelmType.body.font)
                        .foregroundStyle(HelmColor.fgMuted)
                    Link("CoFID publication", destination: URL(string: CoFIDAttribution.sourceURL)!)
                        .font(HelmType.body.font)
                }
                .padding(.vertical, HelmSpacing.xs)
            }

            Section {
                Text(methodologyIntro)
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            ForEach(topicGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.topics) { topic in
                        Button {
                            selectedTopic = topic
                            HapticEngine.shared.play(.selection)
                        } label: {
                            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                                Text(topic.title)
                                    .font(HelmType.label.font)
                                    .foregroundStyle(HelmColor.fg)
                                if let caption = topicCaption(topic) {
                                    Text(caption)
                                        .font(HelmType.monoTag.font)
                                        .foregroundStyle(HelmColor.fgMuted)
                                }
                            }
                        }
                        .buttonStyle(.helmPressable)
                    }
                }
            }

            Section {
                Text("Preferences update your memory profile and re-plan today's session.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Selection bias") {
                Picker("Selection bias", selection: $preferences.selectionBias) {
                    ForEach(MethodologyPreferences.SelectionBias.allCases) { bias in
                        Text(bias.label).tag(bias)
                    }
                }
                .onChange(of: preferences.selectionBias) { _, _ in
                    HapticEngine.shared.play(.selection)
                }

                Text(preferences.selectionBias.detail)
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgMuted)
            }

            Section("Available equipment") {
                Text("Leave all off to allow any equipment. Turn on only what you have access to.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)

                ForEach(MethodologyPreferences.equipmentOptions, id: \.self) { equipment in
                    Toggle(equipmentLabel(equipment), isOn: equipmentBinding(equipment))
                        .onChange(of: preferences.allowedEquipment) { _, _ in
                            HapticEngine.shared.play(.selection)
                        }
                }
            }

            if let saveMessage {
                Section {
                    Text(saveMessage)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
            }

            Section {
                Button(isSaving ? "Saving…" : "Save & Re-plan") {
                    Task { await save() }
                }
                .disabled(isSaving || !isDirty)
            }
        }
        .navigationTitle("Sources & Methodology")
        .helmScreenBackground()
        .scrollContentBackground(.hidden)
        .task {
            MethodologyBootstrap.start()
            await load()
        }
        .sheet(item: $selectedTopic) { topic in
            NavigationStack {
                MethodologyTopicDetailView(topic: topic, evidence: document.evidence(for: topic.citationIDs))
            }
            .helmTheme()
        }
    }

    private var isDirty: Bool {
        preferences != loadedPreferences
    }

    private var methodologyIntro: String {
        if document.placeholder || document.topics.isEmpty {
            return "Methodology library failed to load."
        }
        return "This is the science Signal uses for coaching notes. Essays never change engine maths. Selection bias and equipment below do."
    }

    private var topicGroups: [(title: String, topics: [MethodologyTopic])] {
        let lookup = Dictionary(uniqueKeysWithValues: document.topics.map { ($0.id, $0) })
        var used: Set<String> = []
        var groups: [(title: String, topics: [MethodologyTopic])] = []
        for module in document.modules {
            let topics = module.topicIDs.compactMap { lookup[$0] }
            guard !topics.isEmpty else { continue }
            topics.forEach { used.insert($0.id) }
            groups.append((module.title, topics))
        }
        let orphans = document.topics.filter { !used.contains($0.id) }
        if !orphans.isEmpty {
            groups.append(("Other", orphans))
        }
        return groups
    }

    private func topicCaption(_ topic: MethodologyTopic) -> String? {
        let count = topic.citationIDs.count
        guard count > 0 else { return nil }
        return "\(count) SOURCE\(count == 1 ? "" : "S")"
    }

    @MainActor
    private func load() async {
        document = MethodologyBootstrap.document
        do {
            let profile = try PersistenceBootstrap.persistenceStore.memoryProfile.load()
            let parsed = MethodologyPreferences.parse(from: profile.preferences)
            preferences = parsed.preferences
            loadedPreferences = parsed.preferences
        } catch {
            saveMessage = error.localizedDescription
        }

        await loadPrescriptionCitations()
    }

    @MainActor
    private func loadPrescriptionCitations() async {
        do {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let session = try await prescriptionService.todaysPrescription(readiness: readiness)
            let ids = Array(Set(session.exercises.flatMap(\.evidenceIDs))).sorted()
            prescriptionCitations = document.evidence(for: ids)
                .filter { !$0.placeholder }
        } catch {
            prescriptionCitations = []
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await HelmActionRuntime.perform(
                .trainingPlan(.methodologyPreferences(preferences)),
                after: .coach
            )
            loadedPreferences = preferences
            CloudBackupCoordinator.shared.schedulePush()
            saveMessage = "Saved. Today's prescription was re-planned."
            await loadPrescriptionCitations()
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func equipmentLabel(_ equipment: String) -> String {
        equipment.prefix(1).uppercased() + equipment.dropFirst()
    }

    private func equipmentBinding(_ equipment: String) -> Binding<Bool> {
        Binding(
            get: { preferences.allowedEquipment.contains(equipment) },
            set: { isOn in
                if isOn {
                    preferences.allowedEquipment.insert(equipment)
                } else {
                    preferences.allowedEquipment.remove(equipment)
                }
            }
        )
    }
}

private struct CitationRow: View {
    let record: EvidenceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text(record.title)
                .font(HelmType.label.font)
                .foregroundStyle(HelmColor.fg)
            Text(record.summary)
                .font(HelmType.body.font)
                .foregroundStyle(HelmColor.fgSecondary)
            if !record.citation.isEmpty {
                Text(record.citation)
                    .font(HelmType.monoTag.font)
                    .foregroundStyle(HelmColor.fgMuted)
            }
            if let url = record.url {
                Link(url.host ?? url.absoluteString, destination: url)
                    .font(HelmType.body.font)
            }
        }
        .padding(.vertical, HelmSpacing.xs)
    }
}

#Preview {
    NavigationStack {
        SourcesMethodologyView()
            .onAppear { MethodologyBootstrap.start() }
    }
    .helmTheme()
}
