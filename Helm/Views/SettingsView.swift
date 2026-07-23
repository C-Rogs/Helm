import DesignSystem
import Diagnostics
import SwiftUI

struct SettingsView: View {
    @State private var coordinator = HelmThemeCoordinator.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $coordinator.themeMode) {
                        ForEach(HelmThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: coordinator.themeMode) { _, _ in
                        HapticEngine.shared.play(.selection)
                    }

                    Picker("Layout", selection: $coordinator.skin) {
                        ForEach(HelmSkin.selectableSkins) { skin in
                            Text(skin.label).tag(skin)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: coordinator.skin) { _, _ in
                        HapticEngine.shared.play(.selection)
                    }
                }

                Section("Feedback") {
                    Toggle("Haptics", isOn: $coordinator.hapticsEnabled)
                    Toggle("Threshold insight haptics", isOn: $coordinator.thresholdInsightHapticsEnabled)
                }

                Section("Setup") {
                    NavigationLink("Health Access") {
                        HealthKitOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Health Access")
                    }
                    NavigationLink("Notifications") {
                        NotificationOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Notifications")
                    }
                    NavigationLink("Coach API Key") {
                        CoachKeyOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Coach API Key")
                    }
                    NavigationLink("Training Plan") {
                        TrainingPlanOnboardingStepView(showsFlowControls: false)
                    }
                    NavigationLink("Health Import") {
                        BackfillOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Health Import")
                    }
                    NavigationLink("Shortcuts Setup") {
                        ShortcutsOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Shortcuts Setup")
                    }
                    NavigationLink("Proactive Notifications") {
                        MorningBriefAutomationGuideView()
                    }
                }

                Section {
                    NavigationLink("Training Plan") {
                        PhaseGoalSettingsView()
                    }
                    NavigationLink("Coach") {
                        CoachSettingsView()
                    }
                    NavigationLink("Coach Memory") {
                        MemoryProfileEditorView()
                    }
                    NavigationLink("Sources & Methodology") {
                        SourcesMethodologyView()
                    }
                    NavigationLink("HealthKit") {
                        HealthKitStatusView()
                    }
                    NavigationLink("Watch Sync") {
                        WatchSyncStatusView()
                    }
                    NavigationLink("Data & Backup") {
                        DataSafetyView()
                    }
                    NavigationLink("Schema v2 Export") {
                        SchemaV2ExportView()
                    }
                    NavigationLink("Diagnostics") {
                        DiagnosticsView(environment: ExportEnvironmentFactory.current(
                            schemaVersion: PersistenceBootstrap.schemaVersion
                        ))
                    }
                    #if DEBUG
                    NavigationLink("Stored Data") {
                        DataBrowserView()
                    }
                    #endif
                }
            }
            .navigationTitle("Settings")
            .helmScreenBackground()
        }
        .helmTheme()
    }
}

#Preview {
    SettingsView()
}
